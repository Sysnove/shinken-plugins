#!/bin/bash

E_OK=0
#E_WARNING=1
#E_CRITICAL=2
E_UNKNOWN=3

LAST_RUN_FILE=""
LOGFILE=/var/log/nginx/access.log
FILTER=""
SATISFIED_THRESHOLD=1
APDEX_WARNING=""
APDEX_CRITICAL=""

# process args
while [ -n "$1" ]; do 
    case $1 in
        -l)	shift; LOGFILE=$1 ;;
        -f) shift; FILTER="$1" ;;
        -t) shift; LAST_RUN_FILE=$1 ;;
        -T) shift; SATISFIED_THRESHOLD=$1 ;;
        -W) shift; APDEX_WARNING=$1 ;;
        -C) shift; APDEX_CRITICAL=$1 ;;
        -h)	show_help; exit 1 ;;
    esac
    shift
done

if [ -z "$LOGFILE" ]; then
    echo "UNKNOWN: You need to specify a logfile"
    exit 3
fi

if [ -z "$LAST_RUN_FILE" ]; then
    LAST_RUN_FILE=/var/tmp/nagios/check_website_logs2_last_run_$(echo "$LOGFILE$FILTER" | md5sum | cut -d ' ' -f 1)
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

old_file_pos=1
last_check=-1
# shellcheck disable=SC1090
source "$LAST_RUN_FILE"

new_file_pos=$(wc -l < "$LOGFILE")
now=$(date +%s)

echo "
#LOGFILE=$LOGFILE
old_file_pos=$new_file_pos
last_check=$now
" > "$LAST_RUN_FILE"

if [ "$new_file_pos" -lt "$old_file_pos" ] ; then
    old_file_pos=1
fi

begin=$new_file_pos
end=$old_file_pos

lines () {
    head -n "$begin" "$LOGFILE" | tail --lines=+"$end"
}

nb_lines=$(lines | wc -l)
nb_lines_with_time=$(lines | grep -Ec "$FILTER.* [0-9.]+ [0-9.\-]+$")
total_time=$(lines | grep -E "$FILTER.* [0-9.]+ [0-9.\-]+$" | awk '{s+=$(NF-1)} END {print s}')
p50=$(lines | grep -E "$FILTER.* [0-9.]+ [0-9.\-]+$" | awk '{print $(NF-1)}' | sort | awk '{all[NR] = $0} END{print all[int(NR*0.50)]}')
p95=$(lines | grep -E "$FILTER.* [0-9.]+ [0-9.\-]+$" | awk '{print $(NF-1)}' | sort | awk '{all[NR] = $0} END{print all[int(NR*0.95)]}')
p99=$(lines | grep -E "$FILTER.* [0-9.]+ [0-9.\-]+$" | awk '{print $(NF-1)}' | sort | awk '{all[NR] = $0} END{print all[int(NR*0.99)]}')
max=$(lines | grep -E "$FILTER.* [0-9.]+ [0-9.\-]+$" | awk '{print $(NF-1)}' | sort | tail -n 1)

nb_satisfied=$(lines | grep -E "$FILTER.* [0-9.]+ [0-9.\-]+$" | awk "\$(NF-1) < $SATISFIED_THRESHOLD{print \$(NF-1)}" | wc -l)
nb_tolerated=$(lines | grep -E "$FILTER.* [0-9.]+ [0-9.\-]+$" | awk "\$(NF-1) < ($SATISFIED_THRESHOLD*4){print \$(NF-1)}" | wc -l)
apdex=$(echo "(($nb_satisfied + (($nb_tolerated-$nb_satisfied)/2)) * 100) / $nb_lines_with_time" | bc)

period=$((now - last_check))

rate=$(echo "scale=1; $nb_lines_with_time / $period" | bc |  awk '{printf "%.1f\n", $0}')
pct_lines_with_time=$(echo "($nb_lines_with_time * 100) / $nb_lines" | bc)
time_per_line="$(echo "scale=3; $total_time / $nb_lines_with_time" | bc | awk '{printf "%.3f\n", $0}')"
time_per_line_ms="$(echo "$time_per_line * 1000" | bc | awk '{printf "%.0f\n", $0}')"
#total_estimated_time=$(echo "$time_per_line * $nb_lines" | bc)
load=$(echo "scale=2; ($time_per_line * $nb_lines_with_time) / $period" | bc | awk '{printf "%.2f\n", $0}')

perfdata="rate=${rate}req_per_sec; avg_time_per_request=${time_per_line_ms}ms; load=$load; p50=${p50}ms; p95=${p95}ms; p99=${p99}ms; max=${max}ms; apdex=${apdex}%;$APDEX_WARNING;$APDEX_CRITICAL;0;"

if [ "$pct_lines_with_time" -gt 50 ]; then
    if [ -n "$APDEX_CRITICAL" ] && [ "$apdex" -lt "$APDEX_CRITICAL" ]; then
        echo "Apdex CRITICAL - Apdex ${apdex}% | $perfdata"
    elif [ -n "$APDEXi_WARNING" ] && [ "$apdex" -lt "$APDEX_WARNING" ]; then
        echo "Apdex WARNING - Apdex ${apdex}% | $perfdata"
    else
        echo "OK - $rate requests/second, avg $time_per_line second/request (load $load), Apdex ${apdex}% | $perfdata"
        exit $E_OK
    fi
else
    echo "OK - $rate requests/second (response times not logged) | $perfdata"
    exit $E_OK
fi
