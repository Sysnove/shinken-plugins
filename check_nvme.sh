#!/bin/bash

set -e # exit on error
set -u # error on unset variable
export LC_ALL=C # Force locale to avoid nvme message translations.

usage() {
    cat <<EOF
Basic NVMe check using nvme-cli.

Usage: check_nvme.sh [-s] [-e COUNT] [-m COUNT] -d <device>

Arguments:
    -s         Use sudo
    -e COUNT   Error log entry count critical threshold (default 0).
    -m COUNT   Media error count critical threshold (default 0)
EOF
}

DEVICE=""
SUDO=""
if [ -x /usr/sbin/nvme ]; then
    NVME=/usr/sbin/nvme
else
    echo "Please install nvme-cli."
    exit 2
fi

ERROR_LOG_THRESHOLD=0
MEDIA_ERROR_THRESHOLD=0

while getopts ":se:m:d:" OPTS; do
  case $OPTS in
    s) SUDO="sudo";;
    e) ERROR_LOG_THRESHOLD=true;;
    m) MEDIA_ERROR_THRESHOLD="$OPTARG";;
    d) DEVICE="$OPTARG";;
    *) echo "$USAGE"
       exit 3;;
  esac
done

if [ -z "${DEVICE}" ]
then
  usage
fi

# Read SMART information from nvme-cli
LOG=$(${SUDO} "${NVME}" smart-log "${DEVICE}")

MESSAGES=()
CRIT=false

# Check for critical warning
value_critical_warning=$(echo "${LOG}" | awk '$1 == "critical_warning" {print $3}')
if [ "${value_critical_warning}" -gt 0 ]; then
  CRIT=true
  MESSAGES+=("$DEVICE has critical warning")
fi

# Check media errors
value_media_errors=$(echo "$LOG" | awk '$1 == "media_errors" {print $3}')
if [ "${value_media_errors}" -gt 0 ]; then
  if [ "${value_media_errors}" -ge "${MEDIA_ERROR_THRESHOLD}" ]; then
    CRIT=true
  fi
  MESSAGES+=("$DEVICE has media $value_media_errors errors.")
fi

# Check number of errors logged
value_num_err_log=$(echo "$LOG" | awk '$1 == "num_err_log_entries" {print $3}')
if [ "${value_num_err_log}" -gt 0 ]; then
  if [ "${value_num_err_log}" -ge "${ERROR_LOG_THRESHOLD}" ]; then
    CRIT=true
  fi
  MESSAGES+=("$DEVICE has $value_num_err_log errors logged.")
fi

# Read more data to output as performance data later on
value_temperature=$(echo "$LOG" | awk '$1 == "temperature" {print $3}')
value_available_spare=$(echo "$LOG" | awk '$1 == "available_spare" {print $3}')
value_data_units_written=$(echo "$LOG" | awk '$1 == "data_units_written" {print $3}')
value_data_units_read=$(echo "$LOG" | awk '$1 == "data_units_read" {print $3}')

PERFDATA="media_errors=${value_media_errors} errors=${value_num_err_log} temperature=${value_temperature} available_spare=${value_available_spare} data_units_written=${value_data_units_written}c data_units_read=${value_data_units_read}c"

if $CRIT; then
    echo "CRITICAL: ${MESSAGES[*]}|${PERFDATA}"
  exit 2
else
  echo "OK ${DEVICE}|${PERFDATA}"
  exit 0
fi
