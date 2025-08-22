#!/bin/bash

USER=""
PASSWORD=""
HOST=""
PORT=""

WARN=2
CRIT=4

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
        -w) shift; WARN=$1 ;;
        -c) shift; CRIT=$1 ;;
        -h)	usage; exit 1 ;;
        *) usage; exit 1 ;;
    esac
    shift
done

ARGS=""
[ -n "$USER" ] && ARGS="$ARGS -u $USER"
[ -n "$PASSWORD" ] && ARGS="$ARGS -p $PASSWORD"

if [ -e /usr/bin/mongosh ]; then
    [ -z "$HOST" ] && HOST=localhost
    [ -n "$PORT" ] && ARGS="$HOST:$PORT"
    MONGOCLIENT=/usr/bin/mongosh
else
    [ -n "$HOST" ] && ARGS="$ARGS --host $HOST"
    [ -n "$PORT" ] && ARGS="$ARGS --port $PORT"
    MONGOCLIENT=$(which mongo)
fi

begin=$(date +%s%N | cut -b1-13)
# shellcheck disable=SC2086
db_version=$($MONGOCLIENT $ARGS --eval "db.version()" --quiet)
ret=$?
end=$(date +%s%N | cut -b1-13)

if [ $ret != 0 ] || [ -z "$db_version" ]; then
    echo "UNKNOWN - Could not connect on mongodb"
    exit 3
fi

duration=$((end - begin))

output="MongoDB $db_version is running. Test took $(echo $duration | awk '{printf "%.3f", $1/1000}')s."

if [ "$duration" -gt $((CRIT * 1000)) ]; then
    echo "CRITICAL - $output"
    exit 2
elif [ "$duration" -gt $((WARN * 1000)) ]; then
    echo "WARNING - $output"
    exit 1
else
    echo "OK - $output"
    exit 0
fi
