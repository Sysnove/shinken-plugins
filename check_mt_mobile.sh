#!/bin/sh

AGE_WARN=180
AGE_CRIT=300

# Return codes
OK=0
WARN=1
CRIT=2
UNKN=3

perfdata(){
    if [ -z "${AGE}" ]; then
        printf "'last_updated':Us;%d;%d;0;" "${AGE_WARN}" "${AGE_CRIT}"
    else
        printf "'last_updated':%ds;%d;%d;0;" "${AGE}" "${AGE_WARN}" "${AGE_CRIT}"
    fi
}

ok(){
    printf 'OK: %s | %s\n' "$*" "$(perfdata)"
    exit $OK
}

warn(){
    printf 'WARNING: %s | %s\n' "$*" "$(perfdata)"
    exit $WARN
}

crit(){
    printf 'CRITICAL: %s | %s\n' "$*" "$(perfdata)"
    exit $CRIT
}

unkn(){
    printf 'UNKNOWN: %s | %s\n' "$*" "$(perfdata)"
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
    unkn "Age of test document is empty, please check result: ${RESULT}."
fi

if [ "${AGE}" -gt ${AGE_WARN} ]; then
    warn "Age of test document is over 3 minutes: ${AGE}s."
fi

if [ "${AGE}" -gt ${AGE_CRIT} ]; then
    crit "Age of test document is over 5 minutes : ${AGE}s."
fi

ok "Age of test document is under 3 minutes: ${AGE}s."
