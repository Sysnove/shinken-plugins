#!/bin/bash

USER=""
PASSWORD=""
HOST=""
PORT="27017"
REPLSET_HOST=""

WARN=600
CRIT=3600

usage() {
     sed -rn 's/^### ?//;T;p' "$0"
}

# process args
while [ -n "$1" ]; do 
    case $1 in
        -u)	shift; USER=$1 ;;
        -p) shift; PASSWORD=$1 ;;
        -H) shift; HOST=$1 ;;
        -P) shift; PORT=$1 ;;
        -h) shift; REPLSET_HOST=$1 ;;
        -w) shift; WARN=$1 ;;
        -c) shift; CRIT=$1 ;;
        --help)	usage; exit 1 ;;
        *) usage; exit 1 ;;
    esac
    shift
done

ARGS=""
[ -n "$USER" ] && ARGS="$ARGS -u $USER"
[ -n "$PASSWORD" ] && ARGS="$ARGS -p $PASSWORD"

if [ -e /usr/bin/mongosh ]; then
    [ -z "$HOST" ] && HOST=localhost
    [ -n "$PORT" ] && ARGS="$ARGS $HOST:$PORT"
    MONGOCLIENT=/usr/bin/mongosh
else
    [ -n "$HOST" ] && ARGS="$ARGS --host $HOST"
    [ -n "$PORT" ] && ARGS="$ARGS --port $PORT"
    MONGOCLIENT=/usr/bin/mongo
fi

# shellcheck disable=SC2086
rs_status=$($MONGOCLIENT $ARGS --eval "JSON.stringify(rs.status())" --quiet | jq -r ".members[]")

if [ -z "$rs_status" ]; then
    echo "UNKNOWN - Could not list rs.status() | .members"
    exit 3
fi

status_host=$(echo "$rs_status" | jq -r "select(.name == \"$REPLSET_HOST:$PORT\") | .stateStr")

if [ -z "$status_host" ]; then
    echo "UNKNOWN - Could not find host $REPLSET_HOST in rs.status()"
    exit 3
fi

if [ "$status_host" == "PRIMARY" ]; then
    lag=0
else
    # Secondary, compute lag
    optime_primary=$(echo "$rs_status" | jq -r "select(.stateStr == \"PRIMARY\") | .optimeDate")
    optime_host=$(echo "$rs_status" | jq -r "select(.name == \"$REPLSET_HOST:$PORT\") | .optimeDate")

    ts_optime_primary=$(date -d "$optime_primary" +%s)
    ts_optime_host=$(date -d "$optime_host" +%s)

    lag=$((ts_optime_primary - ts_optime_host)) 
fi

perfdata="replication_lag=$lag;$WARN;$CRIT"

output="$HOST is $status_host, lag is $lag seconds | $perfdata"

if [ "$lag" -gt "$CRIT" ]; then
    echo "CRITICAL - $output"
    exit 2
elif [ "$lag" -gt "$WARN" ]; then
    echo "WARNING - $output"
    exit 1
else
    echo "OK - $output"
    exit 0
fi
