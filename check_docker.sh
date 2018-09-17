#!/bin/sh

docker="$(timeout 5 docker ps -q 2>/dev/null)"
ret=$?

if [ $ret -eq 0 ]; then
    count=$(echo "$docker" | wc -l)
    if [ $count -eq 0 ]; then
        echo "WARNING - 0 running docker container"
        exit 1
    else
        echo "OK - $count running docker container(s)"
        exit 0
    fi
else
    if [ $ret -eq 0 ]; then
        echo "CRITICAL - 'docker ps' timed out after 5 seconds"
        exit 2
    else
        echo "CRITICAL - 'docker ps' returned $ret"
        exit 2
    fi
fi
