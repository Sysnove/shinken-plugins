#!/bin/bash

docker="$(timeout 5 docker ps -q 2>/dev/null)"
ret=$?

# Check if daemon is reachable
if [ $ret -eq 124 ]; then
    echo "CRITICAL - 'docker ps' timed out after 5 seconds"
    exit 2
elif [ $ret -ne 0 ]; then
    echo "CRITICAL - 'docker ps' returned $ret"
    exit 2
fi

# Check if docker uid and gid matches what's expected
if [ -d "/srv/docker-data" ]; then
    docker_data_uid=$(stat -c '%u' /srv/docker-data)
    docker_data_gid=$(stat -c '%g' /srv/docker-data)
    docker_uid="$(id -u docker)"
    docker_gid="$(id -g docker)"

    if [ "$docker_data_uid" != "$docker_uid" ]; then
        echo "CRITICAL - docker uid ($docker_uid) != /srv/docker-data uid ($docker_data_uid)"
        exit 2
    fi
    if [ "$docker_data_gid" != "$docker_gid" ]; then
        echo "CRITICAL - docker gid ($docker_gid) != /srv/docker-data gid ($docker_data_gid)"
        exit 2
    fi
fi

# Check if daemon has been upgraded.
if ! readlink -e "/proc/$(< /var/run/docker.pid)/exe" > /dev/null; then
    echo "CRITICAL - Docker has been upgraded, please schedule a service restart."
    exit 2
fi

count=$(echo "$docker" | wc -l)

if [ "$count" -eq 0 ]; then
    echo "WARNING - 0 running docker container"
    exit 1
fi

echo "OK - $count running docker container(s)"
exit 0
