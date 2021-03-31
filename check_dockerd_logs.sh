#!/bin/bash

###
### This plugin checks /var/log/docker/dockerd.log
### Thresholds allow to detect usual log levels
###
### CopyLeft 2021 Guillaume Subiron <guillaume@sysnove.fr>
###
### Usage : check_dockerd_logs.sh --error-warn 5 --error-crit 10
### Thresholds are events per minute
###

usage() {
     sed -rn 's/^### ?//;T;p' "$0"
}

ERROR_WARN=5
ERROR_CRIT=10
DATEFORMAT=rsyslog

while [ -n "$1" ]; do
    case $1 in
        --error-warn) shift; ERROR_WARN=$1 ;;
        --error-crit) shift; ERROR_CRIT=$1 ;;
        --iso) DATEFORMAT="%O" ;;
        -h) usage; exit 0 ;;
    esac
    shift
done

LOG_FILE="/var/log/docker/dockerd.log"

E_OK=0
E_WARNING=1
E_CRITICAL=2
E_UNKNOWN=3

LAST_RUN_FILE=/var/tmp/nagios/check_dockerd_logs_last_run
NAGIOS_USER=${SUDO_USER:-$(whoami)}
install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$LAST_RUN_FILE")"

if [ -f "$LAST_RUN_FILE" ] && [ ! -O "$LAST_RUN_FILE" ]; then
    echo "UNKNOWN: $LAST_RUN_FILE is not owned by $USER"
    exit $E_UNKNOWN
fi

function compute() {
    echo "$1" | bc -l | awk '{printf "%.1f", $0}'
}

# check logs
if [ -z "$LOG_FILE" ]; then
    echo "File(s) not found : $LOG_FILE"
    exit $E_UNKNOWN
fi

# find last check
if [ ! -f $LAST_RUN_FILE ]; then
    date +%H:%M:%S -d '5 min ago' > $LAST_RUN_FILE
fi

since=$(<$LAST_RUN_FILE)
now=$(date +%H:%M:%S)

echo "$now" > $LAST_RUN_FILE

now_s=$(date -d "$now" +%s)
since_s=$(date -d "$since" +%s)
period=$(( now_s - since_s ))

tmpfile="/tmp/$$.tmp"

/usr/local/bin/dategrep -format "${DATEFORMAT}" --start "$since" "$LOG_FILE" > $tmpfile

total=$(wc -l < $tmpfile)
errors=$(grep -c 'level=error' $tmpfile)
warnings=$(grep -c 'level=warning' $tmpfile)
infos=$(grep -c 'level=info' $tmpfile)
debug=$(grep -c 'level=debug' $tmpfile)

rate_total=$(compute "$total * 60 / $period")
rate_errors=$(compute "$errors * 60 / $period")
rate_warnings=$(compute "$warnings * 60 / $period")
rate_infos=$(compute "$infos * 60 / $period")
rate_debug=$(compute "$debug * 60 / $period")

PERFDATA="log_lines_per_min=$rate_total;;;0; errors_per_min=$rate_errors;$ERROR_WARN;$ERROR_CRIT;0; warnings_per_min=$rate_warnings;;;0; infos_per_min=$rate_infos;;;0; debug_per_min=$rate_debug;;;0;"

RET_MSG="$errors errors over $total lines in the last $period seconds | $PERFDATA"

if (( $(echo "$rate_errors > $ERROR_CRIT" | bc -l) )); then
    RET_CODE=$E_CRITICAL
    RET_MSG="CRITICAL - $RET_MSG"
elif (( $(echo "$rate_warnings > $ERROR_WARN" | bc -l) )); then
    RET_CODE=$E_WARNING
    RET_MSG="WARNING - $RET_MSG"
else
    RET_CODE=$E_OK
    RET_MSG="OK - $RET_MSG"
fi

rm $tmpfile

echo "$RET_MSG"
exit $RET_CODE
