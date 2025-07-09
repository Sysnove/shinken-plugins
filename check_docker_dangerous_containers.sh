#!/bin/bash

if [ "$1" == "-i" ]; then
    ignored_names="$2"
fi

# Find docker containers based on dangerous images, like postgresql
declare count=0
declare count_ignored=0
declare count_pg=0
declare count_mysql=0
declare count_couchbase=0
declare count_couchdb=0
declare count_mongo=0
declare count_elasticsearch=0

# Get containers
containers="$(timeout 5 docker ps --format "{{ .Names }} {{ .Image }} {{ .Ports }}" 2>/dev/null)"
ret=$?

# Check if daemon is reachable
if [ $ret -eq 124 ]; then
    echo "CRITICAL - 'docker ps' timed out after 5 seconds"
    exit 2
elif [ $ret -ne 0 ]; then
    echo "CRITICAL - 'docker ps' returned $ret"
    exit 2
fi

while read -r name image ports; do
    echo "Handling $name ($image)." >&2

    # Filter out known wanted containers
    if grep -qE "^(base_mongo_proxy|registry_portus_mariadb|drone-)" <<< "$name"; then
        echo "Ignoring well known $name." >&2
        continue
    fi

    # Filter out excludes
    if [ -n "$ignored_names" ] && grep -qE "^$ignored_names(\..*)?$" <<< "$name"; then
        echo "Ignoring $name by argument." >&2
        count_ignored=$((count_ignored + 1))
        continue
    fi

    image_name=$(basename "$image" | cut -d':' -f1)

    case $image_name in
        postgres | postgis)
            count_pg=$((count_pg + 1))
            count=$((count + 1))
            ;;
        mysql | mariadb)
            count_mysql=$((count_mysql + 1))
            count=$((count + 1))
            ;;
        counchbase)
            count_couchbase=$((count_couchbase + 1))
            count=$((count + 1))
            ;;
        counchdb)
            count_couchdb=$((count_couchbase + 1))
            count=$((count + 1))
            ;;
        mongo)
            count_mongo=$((count_mongo + 1))
            count=$((count + 1))
            ;;
        elasticsearch)
            count_elasticsearch=$((count_elasticsearch + 1))
            count=$((count + 1))
            ;;
    esac

    count_total=$((count_total + 1))
done <<< "$containers"

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
if [ -n "$count_elasticsearch" ]; then
    msg="$msg$count_elasticsearch elasticsearch, "
fi

if [ "$count_ignored" -gt 0 ]; then
    msg_ignored=" ($count_ignored ignored)"
fi

if [ -n "$count" ]; then
    echo "WARNING - $count dangerous containers running in docker (${msg::-2})$msg_ignored"
    exit 1
fi

echo "OK - no dangerous containers found in docker$msg_ignored"
exit 0
