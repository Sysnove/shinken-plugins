#!/bin/bash

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

# Utility function
usage() {
    cat <<EOF
Usage: $0 [-h HOST[:PORT]] [-u USERNAME] [-p PASSWORD]

Options:
    -h  Host to connect to, default to localhost:8091
    -u  Username used to connect to host
    -p  Password used to connect to host
    -b  Bucket to do an active check with upsert
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

[ ! -x ${JQ} ] && crit "Please install jq."
[ ! -x ${CBQ} ] && crit "Please check cbq path."

# Argument parsing
CBHOST=localhost:8091
DELETEOLDER=-1
WARNING_THRESHOLD=2
CRITICAL_THRESHOLD=7

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
        d)
            DELETEOLDER=$OPTARG
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
CBQOPTS="-quiet -e ${CBHOST}"

if [[ -n "$CBUSER" ]]; then
    CBQOPTS="${CBQOPTS} -user ${CBUSER}"
fi

if [[ -n "$CBPASSWORD" ]]; then
    CBQOPTS="${CBQOPTS} -password ${CBPASSWORD}"
fi

CBQ="${CBQ} ${CBQOPTS}"

# Delete older, may be needed to improve performance.
if [[ "${DELETEOLDER}" -ge 0 ]]; then
    # shellcheck disable=SC2090
    ${CBQ} -script "\
        DELETE FROM system:completed_request \
        WHERE requestTime < date_add_str(now_local(), -${DELETEOLDER}, 'hour');"

    # shellcheck disable=2181
    if [[ $? -ne 0 ]]; then
        crit "Error while running cbq on delete query."
    fi
fi

# Query completed_request
# shellcheck disable=SC2090
RESULT=$(${CBQ} -script "\
SELECT count(*) AS count FROM system:completed_request \
WHERE requestTime > date_add_str(now_local(), -5, 'minute');")

# shellcheck disable=2181
if [[ $? -ne 0 ]]; then
    crit "Error while running cbq on delete query."
fi

COUNT=$(echo "${RESULT}" | ${JQ} '.results[0].count')

# shellcheck disable=2181
if [[ $? -ne 0 ]]; then
    COUNT=U
    crit "Unable to parse cbq result."
fi

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
