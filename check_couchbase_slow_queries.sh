#!/bin/bash

LAST_FILE=/tmp/couchbase_slow

# Return codes
OK=0
WARN=1
CRIT=2
UNKN=3

# Return value (undetermined while not quueried)
COUNT="U"

perfdata() {
    echo -ne " | "
    # Value
    echo -ne "slow_queries=${COUNT};"
    # Thresholds
    echo -ne "${WARNING_THRESHOLD};${CRITICAL_THRESHOLD};"
    # Limits
    echo -ne "0;"
    # New line
    echo
}

# Argument parsing
CBHOST=localhost
WARNING_THRESHOLD=2
CRITICAL_THRESHOLD=7

# Utility function
usage() {
    cat <<EOF
Usage: $0 [-h HOST] [-u USERNAME] [-p PASSWORD]

Options:
    -h  Host to connect to (default: ${CBHOST})
    -u  Username used to connect to host
    -p  Password used to connect to host
    -b  Bucket to do an active check with upsert
    -w  Warning threshold (default: ${WARNING_THRESHOLD})
    -c  Critical threshold (default: ${CRITICAL_THRESHOLD})
EOF

    exit $UNKN
}

warn(){
    echo -ne "WARNING: $*"
    perfdata
    exit $WARN
}

crit(){
    echo -ne "CRITICAL: $*"
    perfdata
    exit $CRIT
}

unkn(){
    echo -ne "UNKNOWN: $*"
    perfdata
    exit $UNKN
}

# Needed binaries
JQ=/usr/bin/jq
CBQ=/opt/couchbase/bin/cbq
CURL=/usr/bin/curl

[ ! -x ${JQ} ] && crit "Please install jq."
[ ! -x ${CBQ} ] && crit "Please check cbq path."
[ ! -x ${CURL} ] && crit "Please check curl path."

while getopts "u:p:h:d:w:c:" option
do
    case $option in
        u)
            CBUSER=$OPTARG
            ;;
        p)
            CBPASSWORD=$OPTARG
            ;;
        h)
            CBHOST=$OPTARG
            ;;
        w)
            WARNING_THRESHOLD=$OPTARG
            ;;
        c)
            CRITICAL_THRESHOLD=$OPTARG
            ;;
        *)
            usage
            ;;
    esac
done

# shellcheck disable=SC2089
CBQOPTS="-quiet -e ${CBHOST}:8093"
CURLOPTS="-s"

if [[ -n "$CBUSER" ]] && [[ -n "${CBPASSWORD}" ]]; then
    CBQOPTS="${CBQOPTS} -user ${CBUSER}"
    CURLOPTS="${CURLOPTS} -u ${CBUSER}:${CBPASSWORD}"
fi

CURL="${CURL} ${CURLOPTS}"
BASE_URL="http://${CBHOST}:8093"
CBQ="${CBQ} ${CBQOPTS}"

UPTIME="$(${CURL} ${BASE_URL}/admin/vitals | ${JQ} -r .uptime)"

# shellcheck disable=2181
if [[ $? -ne 0 ]]; then
    crit "Error while getting vitals."
fi

# parse uptime: 2715h32m7.526712691s
HOURS="$(echo ${UPTIME} | cut -d 'h' -f 1)"
MINUTES="$(echo ${UPTIME} | cut -d 'h' -f 2 | cut -d 'm' -f 1)"
SECONDS="$(echo ${UPTIME} | cut -d 'h' -f 2 | cut -d 'm' -f 2 | cut -d 's' -f 1)"

UPTIME=$(echo "$SECONDS + $MINUTES * 60 + $HOURS * 3600" | bc)

# Query completed_request
# shellcheck disable=SC2090
RESULT="$(${CURL} ${BASE_URL}/admin/stats)"

# shellcheck disable=2181
if [[ $? -ne 0 ]]; then
    crit "Error while getting stats."
fi

COUNT_5000="$(echo "${RESULT}" | jq '.requests_5000ms.count')"
COUNT_1000="$(echo "${RESULT}" | jq '.requests_1000ms.count')"

TOTAL_COUNT="$(echo "${COUNT_1000} + ${COUNT_5000}" | bc)"

if ! [[ -r ${LAST_FILE} ]]; then
    echo "${UPTIME}" > "${LAST_FILE}"
    echo "${TOTAL_COUNT}" >> "${LAST_FILE}"

    unkn "Last file does not exists, creating it."
fi

LAST_UPTIME=$(sed -n 1p ${LAST_FILE})
LAST_TOTAL_COUNT=$(sed -n "2p" ${LAST_FILE})

echo "${UPTIME}" > "${LAST_FILE}"
echo "${TOTAL_COUNT}" >> "${LAST_FILE}"

if [[ ${UPTIME} -lt ${LAST_UPTIME} ]]; then
    unkn "Couchbase has been restarted, resetting stats."
fi

DURATION=$(echo ${UPTIME} - ${LAST_UPTIME} | bc)
COUNT=$(echo "(${TOTAL_COUNT} - ${LAST_TOTAL_COUNT}) / ${DURATION}" | bc)

if [[ ${COUNT} -ge ${CRITICAL_THRESHOLD} ]]; then
    crit "Found more than ${CRITICAL_THRESHOLD} slow queries in last 5 minutes: ${COUNT}"
fi

if [[ ${COUNT} -ge ${WARNING_THRESHOLD} ]]; then
    warn "Found more than ${WARNING_THRESHOLD} slow queries in last 5 minutes: ${COUNT}"
fi

# All good.
echo -ne "OK: Found less than ${WARNING_THRESHOLD} slow queries in last 5 minutes: ${COUNT}"
perfdata
exit $OK
