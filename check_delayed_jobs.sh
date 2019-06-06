#!/bin/sh

DATABASE="$1"
cd /

WARN_THRESHOLD=2
CRIT_THRESHOLD=5

# Check jobs waiting for too long
result=$(sudo -u postgres psql "${DATABASE}" -A -t <<EOF
select count(1)
from delayed_jobs
where locked_by is null
  and failed_at is null
  and created_at < now() - interval '${CRIT_THRESHOLD} minutes'
EOF
)

if [ $result -gt 0 ]; then
    echo "CRITICAL - Found ${result} jobs waiting for more than ${CRIT_THRESHOLD}."
    exit 2
fi

# Get delayed_job PIDs.
PIDS=$(pgrep -fa delayed_job -u mapotempo | sed -re ":a;s/([0-9]+)\\s+(delayed_job\\.[0-9]+)\\s+/'\\2 host:$(hostname) pid:\\1'/;N;s/\\n/, /;ta")

# Check jobs running for too long
result=$(sudo -u postgres psql "${DATABASE}" -A -t <<EOF
select count(1)
from delayed_jobs
where locked_by is null
  and failed_at is null
  and created_at < now() - interval '${CRIT_THRESHOLD} minutes'
  and locked_by in (${PIDS})
EOF
)

if [ $result -gt 0 ]; then
    echo "CRITICAL - Found ${result} jobs waiting for more than ${CRIT_THRESHOLD}."
    exit 2
fi

# Check jobs running for a long time
result=$(sudo -u postgres psql "${DATABASE}" -A -t <<EOF
select count(1)
from delayed_jobs
where locked_by is not null
  and failed_at is null
  and created_at < now() - interval '${WARN_THRESHOLD} minutes'
  and locked_by in (${PIDS})
EOF
)

if [ $result -gt 0 ]; then
    echo "WARNING - Found ${result} jobs waiting for more than ${WARN_THRESHOLD}."
    exit 1
fi

# Check zombie jobs
result=$(sudo -u postgres psql "${DATABASE}" -A -t <<EOF
select count(1)
from delayed_jobs
where locked_by not in (${PIDS})
EOF
)

if [ $result -gt 0 ]; then
    echo "WARNING - Found ${result} zombie jobs."
    exit 1
fi

result=$(sudo -u postgres psql "${DATABASE}" -A -t -c "select (select count(1) from delayed_jobs where locked_by is null and failed_at is null and created_at < now() - interval '0:02:00') > 0 and (select count(1) from delayed_jobs where locked_by is not null) = 0;")

if [ "$result" != "f" ]; then
    echo "CRITICAL - delayed_job may be stalled."
    exit 2
fi

echo "OK - delayed_job is working well."
exit 0

