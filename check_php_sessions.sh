#!/bin/bash

while getopts "e:" option; do
    case $option in
        e)
            EXCLUDES="${EXCLUDES} ${OPTARG}"
            ;;
    esac
done

FIND_OPTS='/'

for EXCLUDE in ${EXCLUDES}; do
    FIND_OPTS="${FIND_OPTS} -path ${EXCLUDE} -prune -o"
done

FIND_OPTS="${FIND_OPTS} -path /usr/share -prune -o"
FIND_OPTS="${FIND_OPTS} -name sess_* -ctime +15 -print"

total=$(nice -n 19 find ${FIND_OPTS} 2>/dev/null | wc -l)

msg="$total PHP old session files found | total=$total;;;;;"

if [ $total -lt 10000 ] ; then
    echo "OK: $msg"
    exit 0
else
    echo "WARNING: $msg"
    exit 1
fi
