#!/bin/bash

file_pos=$(wc -l /var/log/cron.log)

/usr/sbin/service cron force-reload

sleep 1

# shellcheck disable=SC2086
errors=$(tail --lines=+$file_pos /var/log/cron.log | grep 'Error:')

if [ -n "$errors" ]; then
    echo "CRITICAL - Error on cron config : $(echo "$errors" | tail -n 1 | grep -Eo 'Error:.*')"
    exit 2
fi

echo "OK - Cron config is OK"
exit 0
