#!/bin/bash

###
### This plugin checks a web logfile
### and returns req/s, avg response time
### and optionaly p50 (median), p95, p99, max response time
### and Apdex (https://fr.wikipedia.org/wiki/Apdex)
###
### CopyLeft 2025 Guillaume Subiron <guillaume@sysnove.fr>
###
### Usage : 
###   sudo -u nagios ./check_website_logs.sh [-l /var/log/apache2/other_vhosts_access.log] [-f ^example.com] [-T SATISFIED_TRESHOLD] [-W APDEX_WARNING] [-C APDEX_CRITICAL] [-P]
###
### Options :
###   -l LOGFILE              log file to parse (default=/var/log/nginx/access.log)
###   -f FILTER               filter to apply (with grep -E) (default="")
###   -t LAST_RUN_FILE        file to store position between runs (default=/var/tmp/nagios/check_web_log_last_run_*)
###   -T SATISFIED_THRESHOLD  "satisfied" time for apdex (default=1s)
###   -W APDEX_WARNING        apdex warning threshold (no threshold by default)
###   -C APDEX_CRITICAL       apdex critical threhsold (no threshold by default)
###   -P FULL_PERDDATA        display full perfdata, with p50, p95, p99, max and apdex
###
### Examples :
###   sudo -u nagios ./check_website_logs.sh -l /var/log/php-fpm/access.log -f 'www.example.com'
###   sudo -u nagios ./check_website_logs.sh -l /var/log/apache2/www.example.com.log -W 95 -C 90
###

usage() {
     sed -rn 's/^### ?//;T;p' "$0"
}

E_OK=0
E_WARNING=1
E_CRITICAL=2
E_UNKNOWN=3

LAST_RUN_FILE=""
LOGFILE=/var/log/nginx/access.log
FILTER=""
SATISFIED_THRESHOLD=1
APDEX_WARNING=""
APDEX_CRITICAL=""
FULL_PERFDATA=false

# process args
while [ -n "$1" ]; do 
    case $1 in
        -l)	shift; LOGFILE=$1 ;;
        -f) shift; FILTER="$1" ;;
        -t) shift; LAST_RUN_FILE=$1 ;;
        -T) shift; SATISFIED_THRESHOLD=$1 ;;
        -W) shift; APDEX_WARNING=$1; FULL_PERFDATA=true ;;
        -C) shift; APDEX_CRITICAL=$1; FULL_PERFDATA=true ;;
        -P) shift; FULL_PERFDATA=true;;
        -h)	usage; exit 1 ;;
        *) usage; exit 1 ;;
    esac
    shift
done

if [ -z "$LOGFILE" ]; then
    echo "UNKNOWN: You need to specify a logfile"
    exit 3
fi

if [ -z "$LAST_RUN_FILE" ]; then
    LAST_RUN_FILE=/var/tmp/nagios/check_web_log_last_run_$(echo "$LOGFILE$FILTER" | md5sum | cut -d ' ' -f 1)
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
#FILTER=$FILTER
old_file_pos=$new_file_pos
last_check=$now
" > "$LAST_RUN_FILE"

if [ "$new_file_pos" -lt "$old_file_pos" ] ; then
    old_file_pos=1
fi

begin=$new_file_pos
end=$old_file_pos

lines () {
    strings "$LOGFILE" | head -n "$begin" | tail --lines=+"$end" | grep -E "$FILTER"
}

nb_lines=$(lines | wc -l)

# Try nginx format
response_times=$(lines | grep -E "\" [0-9.]+ [0-9.\-]+$" | awk '{print $(NF-1)}' | sort -n)
# Try apache2 format
if [ -z "$response_times" ]; then
    response_times=$(lines | grep -E "\" [0-9]+$" | awk '{print $(NF)/1000}' | sort -n)
fi
# Try php-fpm format
if [ -z "$response_times" ]; then
    response_times=$(lines | grep -E "\" [0-9.]+$"  | awk '{print $(NF)}' | sort -n)
fi

nb_lines_with_time=$(echo "$response_times" | wc -l)
total_time=$(echo "$response_times" | awk '{s+=$1} END {print s}')

period=$((now - last_check))

rate=$(echo "scale=1; $nb_lines_with_time / $period" | bc |  awk '{printf "%.1f\n", $0}')
avg_time="$(echo "scale=3; $total_time / $nb_lines_with_time" | bc | awk '{printf "%.3f\n", $0}')"
avg_time_ms="$(echo "$avg_time * 1000" | bc | awk '{printf "%.0f\n", $0}')"
#total_estimated_time=$(echo "$avg_time * $nb_lines" | bc)
load=$(echo "scale=2; ($avg_time * $nb_lines_with_time) / $period" | bc | awk '{printf "%.2f\n", $0}')

perfdata="rate=${rate}req_per_sec; avg_time_per_request=${avg_time_ms}ms; load=$load;"

if $FULL_PERFDATA; then
    p50=$(echo "$response_times" | awk '{all[NR] = $0} END{print all[int(NR*0.50)]}')
    p95=$(echo "$response_times" | awk '{all[NR] = $0} END{print all[int(NR*0.95)]}')
    p99=$(echo "$response_times" | awk '{all[NR] = $0} END{print all[int(NR*0.99)]}')
    max=$(echo "$response_times" | tail -n 1)

    nb_satisfied=$(echo "$response_times" | awk "\$1 < $SATISFIED_THRESHOLD{print \$1}" | wc -l)
    nb_tolerated=$(echo "$response_times" | awk "\$1 < ($SATISFIED_THRESHOLD*4){print \$1}" | wc -l)
    apdex=$(echo "(($nb_satisfied + (($nb_tolerated-$nb_satisfied)/2)) * 100) / $nb_lines_with_time" | bc)

    perfdata="$perfdata p50=${p50}s; p95=${p95}s; p99=${p99}s; max=${max}s; apdex=${apdex}%;$APDEX_WARNING;$APDEX_CRITICAL;0;"
fi

pct_lines_with_time=$(echo "($nb_lines_with_time * 100) / $nb_lines" | bc)

if [ "$pct_lines_with_time" -gt 50 ]; then
    if [ -n "$APDEX_CRITICAL" ] && [ "$apdex" -lt "$APDEX_CRITICAL" ]; then
        echo "Apdex CRITICAL - Apdex ${apdex}% | $perfdata"
        exit $E_CRITICAL
    elif [ -n "$APDEX_WARNING" ] && [ "$apdex" -lt "$APDEX_WARNING" ]; then
        echo "Apdex WARNING - Apdex ${apdex}% | $perfdata"
        exit $E_WARNING
    else
        echo "OK - $rate requests/second, avg $avg_time second/request (load $load)${apdex:+, Apdex ${SATISFIED_THRESHOLD}s ${apdex}%} | $perfdata"
        exit $E_OK
    fi
else
    echo "OK - $rate requests/second (response times not found) | $perfdata"
    exit $E_OK
fi
