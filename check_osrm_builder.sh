#!/bin/bash

export PATH=/usr/local/bin:/usr/bin:/bin

CONTAINER_NAME=builder_builder_1

# Get container
CONTAINER=$(docker container inspect ${CONTAINER_NAME})

if [ $? -eq 1 ]; then
    # No container running, it's OK
    echo "CRITICAL - No build currently running."
    return 0
fi

RUNNING=$(echo "${CONTAINER}" | jq -r '.[0].State.Running')

if [ "${RUNNING}" != "true" ]; then
    # Container is not running
    echo "CRITICAL - No build currently running."
    return 0
fi

# Retrieve region
REGION=$(echo ${CONTAINER} | jq -r '.[0].Config.Env[]' | sed -nEe 's/^REGION=(.*)/\1/p')
PROFILE=$(echo ${CONTAINER} | jq -r '.[0].Config.Env[]' | sed -nEe 's/^PROFILE=(.*)/\1/p')

STARTED_AT=$(echo ${CONTAINER} | jq -r '.[0].State.StartedAt')

if [ "${REGION}" = "europe" ]; then
    # Europe, threshold is 72 hours
    THRESHOLD=$((72*3600))
else
    # Everything else, threshold is 4 hours
    THRESHOLD=$((4*3600))
fi

# Compute running duration in hours
DURATION=$(( $(date +%s) - $(date -d "${STARTED_AT}" +%s) ))

if [ "${DURATION}" -gt "${THRESHOLD}" ]; then
    echo "CRITICAL - Builder is running more than ${DURATION} hours on region ${REGION} and profile ${PROFILE}."
    exit 2
fi

echo "OK - Builder is running since $(date -d ${STARTED_AT} +%c) on region ${REGION} and profile ${PROFILE}."
exit 0
