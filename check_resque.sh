#!/bin/bash

REDIS_CLI="redis-cli --raw"

PENDING_WARN=10
PENDING_CRIT=20

resque(){
    APP_ENV=production /usr/bin/bundle exec ruby -e "require 'resque'; puts $*.to_json"
}

output() {
    echo "$* |${PERFDATA}"
}

ok() {
    output "OK: $*"
    exit 0
}

warning() {
    output "WARNING: $*"
    exit 1
}

critical() {
    output "CRITICAL: $*"
    exit 2
}

unknown() {
    output "UNKNOWN: $*"
    exit 3
}

usage() {
    unknown "Usage: $0 [-w warn_threshold] [-c crit_threshold]"
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

if [ ! -x /usr/bin/jq ]; then
    unknown "Please install jq."
fi

if [ ${PENDING_WARN} -gt ${PENDING_CRIT} ]; then
    unknown "Pending warning threshold must be below critical one."
fi

if [ ${PENDING_WARN} -lt 0 -o ${PENDING_CRIT} -lt 0 ]; then
    unknown "Thresholds must be positive integers."
fi

cd /srv/mapotempo/optimizer-api

#QUEUES=$(${REDIS_CLI} smembers resque:queues)
QUEUES="SMALL LARGE"

PERFDATA=""

# Get queues
for QUEUE in ${QUEUES}; do
    PENDING=$(resque "Resque.size('${QUEUE}')")
    WORKING=$(resque "Resque::Worker.working().select{ |v| v.queues().include? '${QUEUE}' }.size")
    WORKERS=$(resque "Resque::Worker.all().select{ |v| v.queues().include? '${QUEUE}' }.size")

    if [ ${PENDING} -gt 0 -a ${WORKING} -lt ${WORKERS}  ]; then
        CRITICAL="There are pending jobs and idle workers for queue ${QUEUE}, something is wrong, please check."
    fi

    if [ ${PENDING} -ge ${PENDING_CRIT} ]; then
        CRITICAL="There are at least ${PENDING_CRIT} pending jobs (${PENDING}) for queue ${QUEUE}."
    fi

    if [ ${PENDING} -ge ${PENDING_WARN} ]; then
        WARNING="There are at least ${PENDING_WARN} pending jobs (${PENDING}) for queue ${QUEUE}."
    fi

    PERFDATA="${PERFDATA} ${QUEUE}.workers=${WORKING};;;0;${WORKERS}"
    PERFDATA="${PERFDATA} ${QUEUE}.pending=${PENDING};${PENDING_WARN};${PENDING_CRIT};0;;"
done

[ -n "${CRITICAL}" ] && critical ${CRITICAL}
[ -n "${WARNING}" ] && warning ${WARNING}

ok "All queues are fine."
