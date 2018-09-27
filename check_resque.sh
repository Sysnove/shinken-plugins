#!/bin/bash

OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

WORKERS=0
WORKING=0
PENDING=0


PENDING_WARN=10
PENDING_CRIT=20

output() {
    echo "$* | workers=${WORKERS};;;0; working=${WORKING};;;0;${WORKKERS} pending=${PENDING};${PENDING_WARN};${PENDING_CRIT};0;"
}

ok() {
    output "OK: $*"
    exit ${OK}
}

warning() {
    output "WARNING: $*"
    exit ${WARNING}
}

critical() {
    output "CRITICAL: $*"
    exit ${CRITICAL}
}

unknown() {
    output "UNKNOWN: $*"
    exit ${UNKNOWN}
}

usage() {
    echo "Usage: $0 [-w warn_threshold] [-c crit_threshold]"
    exit ${UNKNOWN}
}


while getopts ":w:c:" option; do
    case "${option}" in
        w)
            PENDING_WARN=${OPTARG}
            ;;
        c)
            PENDING_CRIT=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ ${PENDING_WARN} -gt ${PENDING_CRIT} ]; then
    unknown "Pending warning threshold must be below critical one."
fi

if [ ${PENDING_WARN} -lt 0 -o ${PENDING_CRIT} -lt 0 ]; then
    unknown "Thresholds must be positive integers."
fi

cd /srv/mapotempo/optimizer-api

RESULT=$(env APP_ENV=production RAILS_ENV=production QUEUE=SMALL /usr/bin/bundle exec ruby -e "require 'resque'; puts Resque.info.to_json")

if [ $? -ne 0 ]; then
    critical "Failed to execute command: ${RESULT}"
fi

# {"pending":0,"processed":0,"queues":0,"workers":4,"working":0,"failed":0,"servers":["redis://127.0.0.1:6379/0"],"environment":"production"}

WORKERS=$(echo ${RESULT} | jq .workers)
WORKING=$(echo ${RESULT} | jq .working)
PENDING=$(echo ${RESULT} | jq .pending)

if [ ${PENDING} -gt 0 -a ${WORKING} -lt ${WORKERS}  ]; then
    critical "There are pending jobs and idle workers, something is wrong, please check."
fi

if [ ${PENDING} -ge ${PENDING_CRIT} ]; then
    critical "There are at least ${PENDING_CRIT} pending jobs (${PENDING})."
fi

if [ ${PENDING} -ge ${PENDING_WARN} ]; then
    warning "There are at least ${PENDING_WARN} pending jobs (${PENDING})."
fi

ok "Resque is fine."
