#!/bin/sh

# Find docker containers based on dangerous images, like postgresql

images="$(timeout 5 docker ps --format {{.Image}} 2>/dev/null)"
ret=$?

# Check if daemon is reachable
if [ $ret -eq 124 ]; then
    echo "CRITICAL - 'docker ps' timed out after 5 seconds"
    exit 2
elif [ $ret -ne 0 ]; then
    echo "CRITICAL - 'docker ps' returned $ret"
    exit 2
fi

count=$(echo "$images" | egrep '(postgres|postgis)' | wc -l)

if [ $count -gt 0 ]; then
    echo "WARNING - $count dangerous containers running in docker"
    exit 1
fi

echo "OK - no dangerous container found in docker"
exit 0
