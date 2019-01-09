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
CBHOST=localhost:8091

while getopts "u:p:h:" option
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

BASEURL="http://${CBHOST}"

# Default jq options
JQOPTS="--raw-output"

JQ="${JQ} ${JQOPTS}"

# Debug
#echo ${CURL} ${BASEURL}/pools/default

# Get status
STATUS=$(${CURL} ${BASEURL}/pools/default)

[ $? != 0 ] && crit "Unable to contact couchbase server on ${CBHOST}."

#echo ${STATUS} | ${JQ} .

# Get node status
NODES=$(echo ${STATUS} | ${JQ} ".nodes | length")

for i in $(seq 0 $((${NODES} - 1))); do
    NODEHOST=$( echo ${STATUS} | ${JQ} ".nodes[${i}].hostname")
    NODESTATUS=$( echo ${STATUS} | ${JQ} ".nodes[${i}].status")

    case "${NODESTATUS}" in
        "healthy")
            # Node is healthy, do nothing.
            ;;
        "unhealthy")
            crit "Node ${NODEHOST} is unhealthy."
            ;;
        "warmup")
            warn "Node ${NODEHOST} is warming up."
            ;;
        *)
            unkn "Node status ${NODESTATUS} is not handled for host ${NODEHOST}."
            ;;
    esac
done

# Check balanced
BALANCED=$(echo ${STATUS} | ${JQ} ".balanced")

if [ "${BALANCED}" != "true" ]; then
    REBALANCESTATUS=$(echo ${STATUS} | ${JQ} ".rebalanceStatus")

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

echo "OK: Cluster is healthy with ${NODES} balanced nodes."

exit ${OK}
