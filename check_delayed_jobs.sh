#!/bin/sh

DATABASE="$1"
EXPECTED_WORKERS=2

cd /

WARN_THRESHOLD=1
CRIT_THRESHOLD=3

# Check count of waiting jobs.
WAITING=$(sudo -u postgres psql "${DATABASE}" -A -t <<EOF
select count(1)
from delayed_jobs
where locked_by is null
  and failed_at is null
EOF
)

# Get delayed_job PIDs.
PID_ARRAY=$(pgrep -fa delayed_job -u mapotempo | sed -re ":a;s/([0-9]+)\\s+(delayed_job\\.[0-9]+)\\s+/'\\2 host:$(hostname) pid:\\1'/;N;s/\\n/, /;ta")
PID_COUNT=$(pgrep -f delayed_job -u mapotempo | wc -l)

if [ ${PID_COUNT} -ne ${EXPECTED_WORKERS} ]; then
    echo "CRITICAL - Found ${PID_COUNT} workers but ${EXPECTED_WORKERS} are expected."
    exit 2
fi

# Get count of running jobs.
RUNNING=$(sudo -u postgres psql "${DATABASE}" -A -t <<EOF
select count(1)
from delayed_jobs
where locked_by is null
  and failed_at is null
  and locked_by in (${PID_ARRAY})
EOF
)

if [ ${WAITING} -ge ${CRIT_THRESHOLD} ]; then
    echo "CRITICAL - Found ${WAITING} jobs waiting."
    exit 2
fi

if [ ${WAITING} -gt 0 ]; then

    if [ ${RUNNING} -lt ${EXPECTED_WORKERS} ]; then
        echo "CRITICAL - Found ${WAITING} jobs and only ${RUNNING} running jobs (expected ${EXPECTED_WORKERS})"
        exit 2
    fi
fi

if [ ${WAITING} -ge ${WARN_THRESHOLD} ]; then
    echo "WARNING - Found ${WAITING} jobs waiting."
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

echo "OK - delayed_job is working well."
exit 0
