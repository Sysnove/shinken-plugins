#!/bin/bash

# Find docker containers based on dangerous images, like postgresql

# Get containers
containers="$(timeout 5 docker ps --format "{{.Names}}" 2>/dev/null)"
ret=$?

# Check if daemon is reachable
if [ $ret -eq 124 ]; then
    echo "CRITICAL - 'docker ps' timed out after 5 seconds"
    exit 2
elif [ $ret -ne 0 ]; then
    echo "CRITICAL - 'docker ps' returned $ret"
    exit 2
fi

# Filter out known wanted containers
containers=$(echo "$containers" | egrep -v "(base_mongo_proxy|registry_portus_mariadb)")

# Get images
images=$(echo "$containers" | xargs -l docker container inspect --format "{{ .Config.Image }}")

for image in $images; do
    image_name=$(basename $image | cut -d':' -f1)

    case $image_name in
        postgres | postgis)
            count_pg=$(($count_pg+1))
            count=$(($count+1))
            ;;
        mysql | mariadb)
            count_mysql=$(($count_mysql+1))
            count=$(($count+1))
            ;;
        counchbase)
            count_couchbase=$(($count_couchbase+1))
            count=$(($count+1))
            ;;
        counchdb)
            count_couchdb=$(($count_couchbase+1))
            count=$(($count+1))
            ;;
        mongo)
            count_mongo=$((count_mongo+1))
            count=$(($count+1))
            ;;
    esac

    count_total=$((count_total+1))
done

msg=''
if [ -n "$count_pg" ]; then
    msg="$msg$count_pg postgres, "
fi
if [ -n "$count_mysql" ]; then
    msg="$msg$count_mysql mysql, "
fi
if [ -n "$count_couchbase" ]; then
    msg="$msg$count_couchbase couchbase, "
fi
if [ -n "$count_couchdb" ]; then
    msg="$msg$count_couchdb couchdb, "
fi
if [ -n "$count_mongo" ]; then
    msg="$msg$count_mongo mongo, "
fi

if [ -n "$count" ]; then
    echo "WARNING - $count dangerous containers running in docker (${msg::-2})"
    exit 1
fi

echo "OK - no dangerous containers found in docker"
exit 0
