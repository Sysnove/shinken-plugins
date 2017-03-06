#!/bin/sh

CONTAINER=$1

critical(){
    echo $*
    exit 2
}

RESULT=$(/usr/bin/docker container inspect ${CONTAINER})

if [ $? -ne 0 ]; then
    critical "Container with name '${CONTAINER}' does not exist."
fi

echo ${RESULT} | jq -e '.[0].State.Running' >/dev/null || critical "Container '${CONTAINER}' is stopped."

SINCE=$(echo ${RESULT} | jq -re '.[0].State.StartedAt')

echo "Container '${CONTAINER}' is running since ${SINCE}."
exit 0
