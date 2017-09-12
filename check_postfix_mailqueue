#!/bin/bash
#
# Guillaume Subiron, Sysnove, 2016
# Inspired by Bjoern Bongermino's check_postfix_mailqueue
#
# Copyright 2016 Guillaume Subiron <guillaume@sysnove.fr>
#
# GPL License: http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# Uncomment to enable debugging
# set -x

PROGNAME=`basename $0`
VERSION="Version 1.0"
AUTHOR="Guillaume Subiron (http://www.sysnove.fr/)"

STATE_OK=0
STATE_WARN=1
STATE_CRIT=2
STATE_UNKNOWN=3

warning=0
critical=0

config_dir="/etc/postfix"

print_version() {
    echo "$PROGNAME $VERSION $AUTHOR"
}

print_help() {
    print_version $PROGNAME $VERSION
    echo ""
    echo "$PROGNAME - Checks postfix mailqueue statistic"
    echo ""
    echo "$PROGNAME is a Nagios plugin which generates statistics"
    echo "for the postfix mailqueue and checks for corrupt messages."
    echo "The following values will be checked:"
    echo "maildrop: Localy posted mail"
    echo "incoming: Processed local mail and received from network"
    echo "active: Mails being delivered (should be small)"
    echo "deferred: Stuck mails (that will be retried later)"
    echo "corrupt: Messages found to not be in correct format (should be 0)"
    echo "hold: Recent addition, messages put on hold indefinitly - delete of free"
    echo ""
    echo "Usage: $PROGNAME --deferred_warn Deferred-WARN-Level --deferred_crit Deferred-CRIT-Level --active_warn Active-WARN-Level […]"
    echo ""
    echo "By default, all thresholds are 0 except corrupt_crit"
    echo ""
    echo "Options:"
    echo "  --deferred_warn)"
    echo "     Warning level for deferred mails"
    echo "  --deferred_crit)"
    echo "     Critical level for deferred mails"
    echo "  --active_warn)"
    echo "     Warning level for active mails"
    echo "  --active_crit)"
    echo "     Critical level for active mails"
    echo "  --maildrop_warn)"
    echo "     Warning level for maildrop mails"
    echo "  --maildrop_crit)"
    echo "     Critical level for maildrop mails"
    echo "  --incoming_warn)"
    echo "     Warning level for incoming mails"
    echo "  --incoming_crit)"
    echo "     Critical level for incoming mails"
    echo "  --corrupt_warn)"
    echo "     Warning level for corrupt mails"
    echo "  --corrupt_crit)"
    echo "     Critical level for corrupt mails (default=1)"
    echo "  --hold_warn)"
    echo "     Warning level for hold mails"
    echo "  --hold_crit)"
    echo "     Critical level for hold mails"
    echo "  --config_dir)"
    echo "     Postfix config directory (default=/etc/postfix)"
    echo "  -h)"
    echo "     This help"
    echo "  -v)"
    echo "     Version"
    exit $STATE_OK
}

print_output() {
    values=""
    perfdata=""
    for i in deferred active maildrop incoming corrupt hold; do
        values="${values}${i^}=${!i} "
        warn_var="${i}_warn"
        crit_var="${i}_crit"
        perfdata="$perfdata$i=${!i};${!warn_var};${!crit_var}; "
    done
    echo -n "Postfix Mailqueue $2 is $1 - $values| $perfdata"
}

# Check for parameters
while test -n "$1"; do
    case "$1" in
        -h)
            print_help
            exit $STATE_OK;;
        -v)
            print_version
            exit $STATE_OK;;
        --config_dir)
            config_dir=$2
            shift
            ;;
        --deferred_warn)
            deferred_warn=$2
            shift
            ;;
        --deferred_crit)
            deferred_crit=$2
            shift
            ;;
        --active_warn)
            active_warn=$2
            shift
            ;;
        --active_crit)
            active_crit=$2
            shift
            ;;
        --maildrop_warn)
            maildrop_warn=$2
            shift
            ;;
        --maildrop_crit)
            maildrop_crit=$2
            shift
            ;;
        --incoming_warn)
            incoming_warn=$2
            shift
            ;;
        --incoming_crit)
            incoming_crit=$2
            shift
            ;;
        --corrupt_warn)
            corrupt_warn=$2
            shift
            ;;
        --corrupt_crit)
            corrupt_crit=$2
            shift
            ;;
        --hold_warn)
            hold_warn=$2
            shift
            ;;
        --hold_crit)
            hold_crit=$2
            shift
            ;;
        *)
            print_help
            ;;
    esac
    shift
done

if [ -z $corrupt_crit ]; then
    corrupt_crit=1
fi

# Can be set via environment, but default is fetched by postconf (if available,
# else /var/spool/postfix) 
if which postconf > /dev/null ; then
    SPOOLDIR=${spooldir:-`postconf -c "$config_dir" -h queue_directory`}
else
    SPOOLDIR=${spooldir:-/var/spool/postfix}
fi

cd $SPOOLDIR >/dev/null 2>/dev/null || {
    echo -n "Cannot cd to $SPOOLDIR"
    exit $STATE_CRIT
}

# Get values
for i in deferred active maildrop incoming corrupt hold; do
    eval $i=`(test -d $i && find $i -type f ) | wc -l`
done

for state in crit warn; do
    for i in deferred active maildrop incoming corrupt hold; do
        threshold_var="${i}_${state}"
        value=${!i}
        threshold=${!threshold_var}
        if [ -n "$threshold" ] && [ $value -ge $threshold ]; then
            print_output ${state^^} $i 
            return_var="STATE_${state^^}"
            exit ${!return_var}
        fi
    done
done

print_output OK
exit $STATE_OK
