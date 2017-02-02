#!/bin/sh

DATABASE="$1"
cd /

result=$(sudo -u postgres psql "${DATABASE}" -A -t -c "select (select count(1) from delayed_jobs where locked_by is null and failed_at is null and created_at < now() - interval '0:02:00') > 0 and (select count(1) from delayed_jobs where locked_by is not null) = 0;")

if [ "$result" != "f" ]; then
    echo "CRITICAL - delayed_job may be stalled."
    exit 2
fi

echo "OK - delayed_job is working well."
exit 0

