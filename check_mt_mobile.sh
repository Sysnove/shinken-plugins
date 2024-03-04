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
        printf "last_updated=Us;%d;%d;;" "${AGE_WARN}" "${AGE_CRIT}"
    else
        printf "last_updated=%ds;%d;%d;;" "${AGE}" "${AGE_WARN}" "${AGE_CRIT}"
    fi
}

ok(){
    printf 'OK: %s |%s\n' "$*" "$(perfdata)"
    exit $OK
}

warn(){
    printf 'WARNING: %s |%s\n' "$*" "$(perfdata)"
    exit $WARN
}

crit(){
    printf 'CRITICAL: %s |%s\n' "$*" "$(perfdata)"
    exit $CRIT
}

unkn(){
    printf 'UNKNOWN: %s |%s\n' "$*" "$(perfdata)"
    exit $UNKN
}

usage() {
    cat >&2 <<EOF
Usage:
    ${0} -h host [-p port] [-u credentials]

Arguments:
    -h host         hostname to check.
    -p port         port to connect to (may be passed in host, but not both, no
                    checks are done on this).
    -u credentials  credentials to pass to curl to avoid 301 Authentication
                    Required.
EOF
    exit $UNKN
}

while getopts ":h:p:u:" arg; do
    case $arg in
        h)
            HOST="${OPTARG}"
            ;;
        p)
            PORT="${OPTARG}"
            ;;
        u)
            CREDENTIALS="${OPTARG}"
            ;;
        *)
            usage
            ;;
    esac
done

if [ -z "${HOST}" ]; then
    crit "Please pass the host as parameter."
fi

if [ -n "${PORT}" ]; then
    HOST="${HOST}:${PORT}"
fi

CURL_OPTS=""

if [ -n "${CREDENTIALS}" ]; then
    CURL_OPTS="${CURL_OPTS} -u ${CREDENTIALS}"
fi

RESULT=$(curl ${CURL_OPTS} -sS "http://${HOST}/db/_changes?limit=1&active_only=false&include_docs=true&filter=_doc_ids&channels=%21&doc_ids=test&feed=normal")

ERROR="$(echo "${RESULT}" | jq -r .error)"

if [ "${ERROR}" != "null" ]; then
    crit "Error while getting document information: ${ERROR}"
fi

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
