#!/bin/sh

CONTAINER=$1

critical(){
    echo "CRITICAL: $*"
    exit 2
}

ok(){
    "echo OK: $*"
    exit 0
}



if ! RESULT=$(/usr/bin/docker container inspect "${CONTAINER}" 2>/dev/null); then
    critical "Container with name '${CONTAINER}' does not exist."
fi

echo "${RESULT}" | jq -e '.[0].State.Running' >/dev/null || critical "Container '${CONTAINER}' is stopped."

SINCE=$(echo "${RESULT}" | jq -r -e '.[0].State.StartedAt')

ok "Container '${CONTAINER}' is running since ${SINCE}."
