#!/bin/bash

E_OK=0
#E_WARNING=1
#E_CRITICAL=2
E_UNKNOWN=3

LAST_RUN_FILE=""
LOGFILE=/var/log/nginx/access.log
FILTER=""

# process args
while [ -n "$1" ]; do 
    case $1 in
        -l)	shift; LOGFILE=$1 ;;
        -f) shift; FILTER="$1" ;;
        -t) shift; LAST_RUN_FILE=$1 ;;
        -h)	show_help; exit 1 ;;
    esac
    shift
done

if [ -z "$LAST_RUN_FILE" ]; then
    LAST_RUN_FILE=/var/tmp/nagios/check_website_logs_last_run_$(echo "$LOGFILE$FILTER" | md5sum | cut -d ' ' -f 1)
fi

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

old_nb_lines=-1
old_nb_lines_with_time=-1
old_total_time=-1
last_check=-1
# shellcheck disable=SC1090
source "$LAST_RUN_FILE"

new_nb_lines=$(grep -Ec "$FILTER" "$LOGFILE")
new_nb_lines_with_time=$(grep -Ec "$FILTER.* [0-9.]+ [0-9.]+$" "$LOGFILE")
new_total_time=$(grep -E "$FILTER.* [0-9.]+ [0-9.]+$" "$LOGFILE" | awk '{s+=$(NF-1)} END {print s}')
now=$(date +%s)

echo "
#LOGFILE=$LOGFILE
old_nb_lines=$new_nb_lines
old_nb_lines_with_time=$new_nb_lines_with_time
old_total_time=$new_total_time
last_check=$now
" > "$LAST_RUN_FILE"

if [ $last_check -eq -1 ]; then
    echo "UNKNOWN - First run, please run the check again."
    exit $E_UNKNOWN
fi

if [ "$new_nb_lines" -lt $old_nb_lines ] ; then
    echo "UNKNOWN - Logs seem to have shrink since last run, please run the check again."
    exit $E_UNKNOWN
fi

nb_lines=$((new_nb_lines - old_nb_lines))
nb_lines_with_time=$((new_nb_lines_with_time - old_nb_lines_with_time))
total_time=$(echo "scale=3; $new_total_time - $old_total_time" | bc)
period=$((now - last_check))

rate=$(bc <<< "scale=1; $nb_lines / $period")
pct_lines_with_time=$(echo "($nb_lines_with_time * 100) / $nb_lines" | bc)
time_per_line="$(echo "scale=3; $total_time / $nb_lines_with_time" | bc | awk '{printf "%.3f\n", $0}')"
time_per_line_ms="$(echo "$time_per_line * 1000" | bc | awk '{printf "%.0f\n", $0}')"
#total_estimated_time=$(echo "$time_per_line * $nb_lines" | bc)
load=$(echo "scale=2; ($time_per_line * $nb_lines) / $period" | bc | awk '{printf "%.2f\n", $0}')

perfdata="rate=${rate}req_per_sec; avg_time_per_request=${time_per_line_ms}ms; load=$load;"

if [ "$pct_lines_with_time" -gt 50 ]; then
    echo "OK - $rate requests/second, avg $time_per_line second/request (load $load) | $perfdata"
    exit $E_OK
else
    echo "OK - $rate requests/second (response times not logged) | $perfdata"
    exit $E_OK
fi
