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

HOST="$1"
PORT="$2"

if [ -z "${HOST}" ]; then
    crit "Please pass the host as parameter."
fi

if [ -n "${PORT}" ]; then
    HOST="${HOST}:${PORT}"
fi

RESULT=$(curl -sS "http://${HOST}/db/_changes?limit=1&active_only=false&include_docs=true&filter=_doc_ids&channels=%21&doc_ids=test&feed=normal")

AGE=$(echo "${RESULT}" | jq --argjson timestamp "$(date +%s)" '$timestamp - (.results[0].doc.touched_at | tonumber)')

if [ "${AGE}" -gt 120 ]; then
    warn "Age of test file is over 2 minutes: ${AGE}s."
fi

if [ "${AGE}" -gt 300 ]; then
    crit "Age of test file is over 5 minutes : ${AGE}s."
fi

echo "Age of test file is under 2 mintues: ${AGE}s."
exit $OK
