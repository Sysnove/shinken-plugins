#!/bin/bash

# user is in parameter 1
USER="$1"

REPOSITORY="dumps"

# Password is in paramter 2, if user is provided
if [ -n "$USER" ]; then
    PASSWORD="$2"
fi

AGE_CRITICAL_THRESHOLD=3
AGE_WARNING_THRESHOLD=1

CURL="/usr/bin/curl"

function curl(){
    PARAMS="-s -H 'Content-Type: application/json'"
    if [ -n "$USER" ]; then
        PARAMS="${PARAMS} --user ${USER}:${PASSWORD}"
    fi

    /usr/bin/curl ${PARAMS} "$@"
}

RESULT=$(curl -X GET http://localhost:9200/_snapshot/$REPOSITORY/_all)

if [ $? -ne 0 ]; then
    echo "CRITICAL - Impossible to connect to ElasticSearch."
    exit 2
fi

ERROR=$(echo "${RESULT}" | jq -e '.error')

# Return code with -e is 1 if query result is null.
if [ $? -ne 1 ]; then
    echo "CRITICAL - An error occured while getting snapshot information: "$(echo ${ERROR} | jq -r '.reason')
    exit 2
fi

RESULT=$(echo "${RESULT}" | jq '.snapshots | map(select(.state == "SUCCESS")) | sort_by(-.end_time_in_millis)')

NB_SNAPSHOTS=$(echo "${RESULT}" | jq 'length')

if [ "${NB_SNAPSHOTS}" -eq 0 ]; then
    echo "CRITICAL - No snapshots found in $REPOSITORY snapshot repository."
    exit 2
fi

if [ "${NB_SNAPSHOTS}" -gt 1 ]; then
    echo "CRITICAL : More than one snapshot found in $REPOSITORY snapshot repository."
    exit 2
fi

# Note: timestamp is in microsecondes.
SECONDS_IN_DAY=$((24*3600))
NOW=$(date +'%s')

TIMESTAMP=$(echo "${RESULT}" | jq '.[0].end_time_in_millis')
AGE_IN_SECONDS=$((${NOW}-${TIMESTAMP}/1000))
AGE_IN_DAYS=$((${AGE_IN_SECONDS} / ${SECONDS_IN_DAY}))

if [ "${AGE_IN_DAYS}" -gt ${AGE_CRITICAL_THRESHOLD} ]; then
    echo "CRITICAL - Backup is older than ${AGE_CRITICAL_THRESHOLD} days."
    exit 2
fi

if [ "${AGE_IN_DAYS}" -gt 1 ]; then
    echo "WARNING - Backup is older than ${AGE_WARNING_THRESHOLD} day."
    exit 1
fi

END_TIME=$(echo "${RESULT}" | jq -r '.[0].end_time')

echo "OK - Last snapshot finished at ${END_TIME}"
exit 0
