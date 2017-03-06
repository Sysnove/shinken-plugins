#!/bin/sh

CONTAINER=$1

critical(){
    echo $*
    exit 2
}

/usr/bin/docker container inspect ${CONTAINER} | jq -e '.[0].State.Running' || critical "Container '${CONTAINER}' is stopped or does not exist."

SINCE=/usr/bin/docker container inspect ${CONTAINER} | jq '.[0].State.StartedAt'

echo "Container '${CONTAINER} is running since ${SINCE}."
exit 0
