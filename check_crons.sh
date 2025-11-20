#!/bin/bash

###
### This plugin checks running crons
### Thresholds allow to detect too many crons running at the same time
### And crons running for too long.
###
### CopyLeft 2025 Guillaume Subiron <guillaume@sysnove.fr>
###
### Usage : check_crons.sh [--max-duration 7] [--max-at-a-time 20]

usage() {
     sed -rn 's/^### ?//;T;p' "$0"
}

MAX_CRON_DURATION=7
MAX_CRONS_AT_A_TIME=20

while [ -n "$1" ]; do
    case $1 in
        --max-duration) shift; MAX_CRON_DURATION=$1 ;;
        --max-at-a-time) shift; MAX_CRONS_AT_A_TIME=$1 ;;
        -h) show_help; exit 1 ;;
    esac
    shift
done

# shellcheck disable=2009
too_long_crons=$(ps -e -o pid,etimes,command | grep CRON -A 1 | grep -v '/usr/sbin/CRON' | awk "{if(\$2>$((MAX_CRON_DURATION * 24 * 3600))) print \$0}" | wc -l)

if [ "$too_long_crons" -gt 0 ]; then
    echo "WARNING - $too_long_crons crons are running from more than $MAX_CRON_DURATION days."
    exit 1
fi

for i in {1..60}; do
    nb=$(grep "$(date --date="$i minutes ago" +'%d %H:%M:0')" /var/log/cron.log | grep -v ':00:0' | grep -v ' (root) ' | grep -c ' CMD ')
    if [ "$nb" -gt "$MAX_CRONS_AT_A_TIME" ]; then
        echo "$nb crons have been called at $(date --date="$i minutes ago" +'%H:%M:00')"
        exit 1
    fi
done
