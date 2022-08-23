#!/bin/bash

E_OK=0
#E_WARNING=1
#E_CRITICAL=2
E_UNKNOWN=3

LAST_RUN_FILE=/var/tmp/nagios/check_haproxy_logs_last_run
LOGFILE=/var/log/haproxy.log
BACKEND_FILTER=""

show_help() {
	echo "todo"
}

# process args
while [ -n "$1" ]; do 
    case $1 in
        -l)	shift; LOGFILE=$1 ;;
        -b) shift; BACKEND_FILTER=" $1[/ ]" ;;
        -t) shift; LAST_RUN_FILE=$1 ;;
        -h)	show_help; exit 1 ;;
    esac
    shift
done

if [ ! -r "$LOGFILE" ]; then
    echo "UNKNOWN : Cannot read $LOGFILE"
    exit 3
fi

NAGIOS_USER=${SUDO_USER:-$(whoami)}
if ! [ -d "$(dirname "$LAST_RUN_FILE")" ]; then
    install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$LAST_RUN_FILE")"
fi

if [ -f "$LAST_RUN_FILE" ] && [ ! -O "$LAST_RUN_FILE" ]; then
    echo "UNKNOWN: $LAST_RUN_FILE is not owned by $USER"
    exit $E_UNKNOWN
fi


old_count=-1
last_check=-1
# shellcheck disable=SC1090
source "$LAST_RUN_FILE"

new_count=$(grep -Ec "$BACKEND_FILTER" "$LOGFILE")
now=$(date +%s)

echo "
old_count=$new_count
last_check=$now
" > "$LAST_RUN_FILE"

if [ $last_check -eq -1 ]; then
    echo "UNKNOWN - First run, please run the check again."
    exit $E_UNKNOWN
fi

if [ "$new_count" -lt $old_count ] ; then
    echo "UNKNOWN - Logs seem to have shrink since last run, please run the check again."
    exit $E_UNKNOWN
fi

count=$((new_count - old_count))
period=$((now - last_check))

rate=$(bc <<< "scale=1; $count / $period")

echo "OK - $count requests in $period seconds ($rate req/s) | rate=${rate}req_per_sec"
exit $E_OK
