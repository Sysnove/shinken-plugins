#!/bin/bash

USER=$1
PASSWORD=$2

if [ -e /usr/bin/mongosh ]; then
    MONGOCLIENT=/usr/bin/mongosh
else
    MONGOCLIENT=/usr/bin/mongo
fi

begin=$(date +%s%N | cut -b1-13)
db_version=$($MONGOCLIENT -u "$USER" -p "$PASSWORD" --eval "db.version()" --quiet)
ret=$?
end=$(date +%s%N | cut -b1-13)

if [ $ret != 0 ] || [ -z "$db_version" ]; then
    echo "UNKNOWN - Could not connect on mongodb"
    exit 3
fi

duration=$((end - begin))

output="MongoDB $db_version is running. Test took $(echo $duration | awk '{printf "%.3f", $1/1000}')s."

if [ "$duration" -gt 4000 ]; then
    echo "CRITICAL - $output"
    exit 2
elif [ "$duration" -gt 2000 ]; then
    echo "WARNING - $output"
    exit 1
else
    echo "OK - $output"
    exit 0
fi
