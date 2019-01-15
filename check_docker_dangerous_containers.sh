#!/bin/bash

# Find docker containers based on dangerous images, like postgresql

images="$(timeout 5 docker ps --format "{{.Image}} {{.Names}}" 2>/dev/null)"
ret=$?

# Check if daemon is reachable
if [ $ret -eq 124 ]; then
    echo "CRITICAL - 'docker ps' timed out after 5 seconds"
    exit 2
elif [ $ret -ne 0 ]; then
    echo "CRITICAL - 'docker ps' returned $ret"
    exit 2
fi

count_pg=$(echo "$images" | egrep '(postgres|postgis)' | wc -l)
count_mysql=$(echo "$images" | egrep '(mysql|mariadb)' | grep -v 'registry_portus_mariadb' | wc -l)
count_couchbase=$(echo "$images" | grep 'couchbase' | wc -l)
count_couchdb=$(echo "$images" | grep 'couchdb' | wc -l)
count_mongo=$(echo "$images" | grep 'mongo' | grep -v 'base_mongo_proxy' | grep -v 'mongo-express' | wc -l)

count=$(($count_pg+$count_mysql+$count_couchbase+$count_couchdb+$count_mongo))

msg=''
if [ $count_pg -gt 0 ]; then
    msg="$msg$count_pg postgres, "
fi
if [ $count_mysql -gt 0 ]; then
    msg="$msg$count_mysql mysql, "
fi
if [ $count_couchbase -gt 0 ]; then
    msg="$msg$count_couchbase couchbase, "
fi
if [ $count_couchdb -gt 0 ]; then
    msg="$msg$count_couchdb couchdb, "
fi
if [ $count_mongo -gt 0 ]; then
    msg="$msg$count_mongo mongo, "
fi

if [ $count -gt 0 ]; then
    echo "WARNING - $count dangerous containers running in docker ($msg)"
    exit 1
fi

echo "OK - no dangerous container found in docker"
exit 0
