#!/bin/bash

USER=$1
PASSWORD=$2
HOST=$3

if [ -e /usr/bin/mongosh ]; then
    MONGOCLIENT=/usr/bin/mongosh
else
    MONGOCLIENT=/usr/bin/mongo
fi

rs_status=$($MONGOCLIENT -u "$USER" -p "$PASSWORD" --eval "JSON.stringify(rs.status())" --quiet | jq -r ".members[]")

if [ -z "$rs_status" ]; then
    echo "UNKNOWN - Could not list rs.status() | .members"
    exit 3
fi

status_host=$(echo "$rs_status" | jq -r "select(.name == \"$HOST:27017\") | .stateStr")

if [ -z "$status_host" ]; then
    echo "UNKNOWN - Could not find host $HOST in rs.status()"
    exit 3
fi

if [ "$status_host" == "PRIMARY" ]; then
    lag=0
else
    # Secondary, compute lag
    optime_primary=$(echo "$rs_status" | jq -r "select(.stateStr == \"PRIMARY\") | .optimeDate")
    optime_host=$(echo "$rs_status" | jq -r "select(.name == \"$HOST:27017\") | .optimeDate")

    ts_optime_primary=$(date -d "$optime_primary" +%s)
    ts_optime_host=$(date -d "$optime_host" +%s)

    lag=$((ts_optime_primary - ts_optime_host)) 
fi

perfdata="replication_lag=$lag;600;3600"

echo "OK - $HOST is $status_host, lag is $lag seconds | $perfdata"
