#!/bin/sh

docker="$(timeout 5 docker ps -q 2>/dev/null)"
ret=$?

# Check if daemon is reachable
if [ $ret -eq 124 ]; then
    echo "CRITICAL - 'docker ps' timed out after 5 seconds"
    exit 2
elif [ $ret -ne 0 ];
    echo "CRITICAL - 'docker ps' returned $ret"
    exit 2
fi

# Check if daemon has been upgraded.
readlink -e /proc/$(< /var/run/docker.pid)/exe > /dev/null

if [ $? -ne 0 ]; then
    echo "CRITICAL - Docker has been upgraded, please schedule a service restart."
    exit 2
fi

count=$(echo "$docker" | wc -l)

if [ $count -eq 0 ]; then
    echo "WARNING - 0 running docker container"
    exit 1
fi

echo "OK - $count running docker container(s)"
exit 0
