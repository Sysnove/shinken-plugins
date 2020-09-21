#!/bin/sh

DATABASE="$1"
EXPECTED_WORKERS="$2"

if [ -z "${DATABASE}" -o -z "${EXPECTED_WORKERS}" ]; then
    echo "CRITICAL - Please provide two parameters : database and expected workers"
    exit 2
fi

cd /

WARN_THRESHOLD=1
CRIT_THRESHOLD=3

output() {
    PERFDATA="'workers'=${PID_COUNT};;;0;${EXPECTED_WORKERS}"
    PERFDATA="${PERFDATA} 'running'=${RUNNING};;;0;${EXPECTED_WORKERS}"
    PERFDATA="${PERFDATA} 'zombies'=${ZOMBIES};;;0;"
    PERFDATA="${PERFDATA} 'waiting'=${WAITING};${WARN_THRESHOLD};${CRIT_THRESHOLD};0;"

    echo "$* | ${PERFDATA}"
}

unknown() {
    output "UNKNOWN - $*"
    exit 3
}

critical() {
    output "CRITICAL - $*"
    exit 2
}

warning() {
    output "WARNING - $*"
    exit 1
}

ok() {
    output "OK - $*"
    exit 0
}

# Get delayed_job PIDs.
PID_ARRAY=$(pgrep -fa delayed_job -u mapotempo | sed -re ":a;s/([0-9]+)\\s+(delayed_job\\.[0-9]+)\\s+/'\\2 host:$(hostname) pid:\\1'/;N;s/\\n/, /;ta")
PID_COUNT=$(pgrep -f delayed_job -u mapotempo | wc -l)

# Get count of waiting jobs.
WAITING=$(sudo -u postgres psql "${DATABASE}" -A -t <<EOF
select count(1)
from delayed_jobs
where locked_by is null
  and failed_at is null
EOF
)

if [ "${PID_COUNT}" -gt 0 ]; then
    # Get count of running jobs.
    RUNNING=$(sudo -u postgres psql "${DATABASE}" -A -t <<EOF
select count(1)
from delayed_jobs
where locked_by is not null
  and failed_at is null
  and locked_by in (${PID_ARRAY})
EOF
    )

    # Get count of zombie jobs
    ZOMBIES=$(sudo -u postgres psql "${DATABASE}" -A -t <<EOF
select count(1)
from delayed_jobs
where locked_by is not null
  and locked_by not in (${PID_ARRAY})
EOF
    )
else
    RUNNING=0

    # Get count of zombie jobs
    ZOMBIES=$(sudo -u postgres psql "${DATABASE}" -A -t <<EOF
select count(1)
from delayed_jobs
where locked_by is not null
EOF
    )
fi

if [ ${PID_COUNT} -ne ${EXPECTED_WORKERS} ]; then
    critical "Found ${PID_COUNT} workers but ${EXPECTED_WORKERS} are expected."
fi

if [ ${WAITING} -ge ${CRIT_THRESHOLD} ]; then
    critical "Found ${WAITING} jobs waiting."
fi

if [ ${WAITING} -gt 1 ]; then
    if [ ${RUNNING} -lt ${EXPECTED_WORKERS} ]; then
        critical "Found ${WAITING} waiting jobs and only ${RUNNING} running jobs (expected ${EXPECTED_WORKERS})."
    fi
fi

if [ ${WAITING} -ge ${WARN_THRESHOLD} ]; then
    warning "Found ${WAITING} waiting jobs."
fi

if [ ${ZOMBIES} -gt 0 ]; then
    warning "Found ${ZOMBIES} zombie jobs."
fi

ok "Found ${RUNNING} running jobs over ${PID_COUNT} workers and ${WAITING} waiting jobs."
exit 0
