#!/bin/sh

# Return codes
OK=0
WARN=1
CRIT=2
UNKN=3

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
    echo "WARNING: $*"
    exit $WARN
}

crit(){
    echo "CRITICAL: $*"
    exit $CRIT
}

unkn(){
    echo "UNKNOWN: $*"
    exit $UNKN
}

# Needed binaries
JQ=/usr/bin/jq
CURL=/usr/bin/curl

[ ! -x ${JQ} ] && crit "Please install jq."
[ ! -x ${CURL} ] && crit "Please install curl."

# Argument parsing
CBHOST=localhost

while getopts "u:p:h:b:" option
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
        b)
            CBBUCKET=$OPTARG
            ;;
        *)
            usage
            ;;
    esac
done

# Build curl options
CURLOPTS="--silent"

if [ -n "${CBUSER}" ];then
    CURLOPTS="${CURLOPTS} --user ${CBUSER}"

    if [ -n "${CBPASSWORD}" ]; then
        CURLOPTS=${CURLOPTS}:${CBPASSWORD}
    fi
fi

CURL="${CURL} ${CURLOPTS}"

# Default jq options
JQOPTS="--raw-output"

JQ="${JQ} ${JQOPTS}"

# Query Couchbase to retrieve cluster status.
if ! STATUS=$(${CURL} "http://${CBHOST}:8091/pools/default"); then
    crit "Unable to contact couchbase server on ${CBHOST}."
fi

# Get current node status.
# shellcheck disable=SC2016
CURRENT_NODE=$(echo "${STATUS}" | ${JQ} --arg FQDN "$(hostname --fqdn)" \
    '.nodes | map(select(.hostname | test("^(" + $FQDN + "|127.0.0.1|localhost)")))[0]')

if [ -z "${CURRENT_NODE}" ] || [ "${CURRENT_NODE}" = "null" ]; then
    crit "No node information found."
fi

NODESTATUS=$(echo "${CURRENT_NODE}" | ${JQ} ".status")

case "${NODESTATUS}" in
    "healthy")
        # Node is healthy, do nothing.
        ;;
    "unhealthy")
        crit "Node is unhealthy."
        ;;
    "warmup")
        warn "Node is warming up."
        ;;
    *)
        unkn "Unknown status: ${NODESTATUS}."
        ;;
esac

# Active check if bucket has been passed
if [ -n "${CBBUCKET}" ]; then
    TIMESTAMP="$(date +%s)"

    QUERY=$(cat <<EOF
UPSERT INTO \`${CBBUCKET}\` (KEY, VALUE)
VALUES ("test", {"type": "test", "info": "do not remove this document", "touched_at": "${TIMESTAMP}"})
RETURNING touched_at;
EOF
)

    RESULT=$(${CURL} "http://${CBHOST}:8093/query/service" --data-urlencode "statement=${QUERY}")

    QUERYSTATUS=$(echo "${RESULT}" | ${JQ} '.status')

    if [ "${QUERYSTATUS}" != "success" ]; then
        crit "Impossible to upsert test document."
    fi
fi

# Check balanced
NODE_COUNT=$(echo "${STATUS}" | ${JQ} ".nodes | length")
BALANCED=$(echo "${STATUS}" | ${JQ} ".balanced")

if [ "${BALANCED}" != "true" ]; then
    REBALANCESTATUS=$(echo "${STATUS}" | ${JQ} ".rebalanceStatus")

    case "${REBALANCESTATUS}" in
        "running")
            warn "Cluster is not balanced and rebalance is running."
            ;;
        "none")
            crit "Cluster is not balanced and no rebalance is in progress."
            ;;
        *)
            crit "Cluster is not balanced and rebalance status is ${REBALANCESTATUS}."
            ;;
    esac
fi

printf "OK: Cluster is healthy with %s balanced nodes" "${NODE_COUNT}"

if [ -n "${CBBUCKET}" ]; then
    printf " and upsert test was successfull"
fi

echo "."

exit ${OK}
