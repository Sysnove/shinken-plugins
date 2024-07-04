#!/bin/bash

last_line=$(grep FINISHED /var/log/backupninja.log | tail -n 1)

if [ -z "$last_line" ] && [ -f /var/log/backupninja.log.1.gz ]; then
    last_line=$(zgrep FINISHED /var/log/backupninja.log.1.gz | tail -n 1)
fi

if [ -z "$last_line" ]; then
    echo "UNKNOWN"
    exit 3
fi

last_line_date=$(echo "$last_line" | cut -d ' ' -f 1-3)
last_line_ts=$(date --date="$last_line_date" +%s)
now_ts=$(date +%s)
last_line_date=$(date --date="$last_line_date" +"%Y-%m-%d %H:%M:%S")


if [ $((now_ts - last_line_ts)) -gt $((60*60*52)) ]; then
    echo "CRITICAL - Last backup has finished more than 52 hours from now ($last_line_date)"
    exit 2
fi

nb_fatal=$(echo "$last_line" | grep -Eo '[0-9]+ fatal' | cut -d ' ' -f 1)
nb_error=$(echo "$last_line" | grep -Eo '[0-9]+ error' | cut -d ' ' -f 1)
nb_warning=$(echo "$last_line" | grep -Eo '[0-9]+ warning' | cut -d ' ' -f 1)

if [ "$nb_fatal" -gt 0 ]; then
    echo "CRITICAL - $nb_fatal fatal errors in last backupninja run ($last_line_date)"
fi

if [ "$nb_error" -gt 0 ]; then
    echo "CRITICAL - $nb_error errors in last backupninja run ($last_line_date)"
fi

if [ $((now_ts - last_line_ts)) -gt $((60*60*27)) ]; then
    echo "WARNING - Last backup has finished more than 27 hours from now ($last_line_date)"
    exit 1
fi

if [ "$nb_warning" -gt 0 ]; then
    echo "WARNING - $nb_warning warnings in last backupninja run ($last_line_date)"
fi
