#!/bin/sh

# Return codes
OK=0
WARN=1
CRIT=2
UNKN=3

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

RESULT_COUNT=$(echo "${RESULT}" | jq '.results | length')

if [ "${RESULT_COUNT}" -eq 0 ]; then
    crit "No result found, test document is not present."
fi

AGE=$(echo "${RESULT}" | jq --argjson timestamp "$(date +%s)" '$timestamp - (.results[0].doc.touched_at | tonumber)')

if [ -z "${AGE}" ]; then
    unkn "Age is empty, please check result: ${RESULT}."
fi

if [ "${AGE}" -gt 180 ]; then
    warn "Age of test file is over 3 minutes: ${AGE}s."
fi

if [ "${AGE}" -gt 300 ]; then
    crit "Age of test file is over 5 minutes : ${AGE}s."
fi

echo "OK: Age of test file is under 3 minutes: ${AGE}s."
exit $OK
