#!/bin/bash
set -e # exit on error
set -u # error on unset variable
export LC_ALL=C

#
# Simple monitoring check for nvme devices
# Requires: nvme-cli
# Usage: check_nvme.sh -d <device>
#
# Author: Matthias Geerdsen <mg@geerdsen.net>
# Copyright (C) 2017 Matthias Geerdsen
#
# This program is ifree software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

USAGE="Usage: check_nvme.sh [-s] [-e] -d <device>
  -s .. call nvme smart-log using sudo
  -e .. ignore num_err_log_entries for state
"
DISK=""
SUDO=""
if [ -x /usr/sbin/nvme ]; then
    NVME=/usr/sbin/nvme
else
    NVME=nvme
fi

while getopts ":sed:" OPTS; do
  case $OPTS in
    s) SUDO="sudo";;
    e) IGNORE_ERR_LOG_ENTRIES="1";;
    d) DISK="$OPTARG";;
    *) echo "$USAGE"
       exit 3;;
  esac
done

if [ -z "$DISK" ]
then
  echo "$USAGE"
  exit 3
fi


# read smart information from nvme-cli
LOG=$(${SUDO} ${NVME} smart-log ${DISK})

MESSAGE=""
CRIT=false

# Check for critical warning
value_critical_warning=$(echo "$LOG" | awk '$1 == "critical_warning" {print $3}')
if [ $value_critical_warning != 0 ]; then
  CRIT=true
  MESSAGE="$MESSAGE $DISK has critical warning "
fi

# Check media errors
value_media_errors=$(echo "$LOG" | awk '$1 == "media_errors" {print $3}')
if [ $value_media_errors != 0 ]; then
  CRIT=true
  MESSAGE="$MESSAGE $DISK has media errors ($value_media_errors) "
fi

# Check number of errors logged
value_num_err_log=$(echo "$LOG" | awk '$1 == "num_err_log_entries" {print $3}')
if [ $value_num_err_log != 0 ]; then
  if [ -z ${IGNORE_ERR_LOG_ENTRIES+USET} ]; then
    CRIT=true
  fi
  MESSAGE="$MESSAGE $DISK has errors logged ($value_num_err_log) "
fi

# Read more data to output as performance data later on
value_temperature=$(echo "$LOG" | awk '$1 == "temperature" {print $3}')
value_available_spare=$(echo "$LOG" | awk '$1 == "available_spare" {print $3}')
value_data_units_written=$(echo "$LOG" | awk '$1 == "data_units_written" {print $3}')
value_data_units_read=$(echo "$LOG" | awk '$1 == "data_units_read" {print $3}')

PERFDATA="media_errors=${value_media_errors} errors=${value_num_err_log} temperature=${value_temperature} available_spare=${value_available_spare} data_units_written=${value_data_units_written}c data_units_read=${value_data_units_read}c"

if [ $CRIT = "true" ]; then
  echo "CRITICAL: ${MESSAGE}|${PERFDATA}"
  exit 2
else
  echo "OK ${DISK}|${PERFDATA}"
  exit 0
fi
