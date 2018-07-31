#!/bin/bash

NUMBER=10000
AGE=15

while getopts "e:n:a:" option; do
    case $option in
        e)
            EXCLUDES="${EXCLUDES} ${OPTARG}"
            ;;
        n)
            NUMBER=${OPTARG}
            ;;
        a)
            AGE=${OPTARG}
            ;;
    esac
done

FIND_OPTS='/'

for EXCLUDE in ${EXCLUDES}; do
    FIND_OPTS="${FIND_OPTS} \! -path ${EXCLUDE}"
done

FIND_OPTS="${FIND_OPTS} \! -path /usr/share"
FIND_OPTS="${FIND_OPTS} -regextype posix-egrep -regex .*/(ci_session|sess_).* -ctime +${AGE} -print"

total=$(nice -n 19 find ${FIND_OPTS} 2>/dev/null | wc -l)

msg="$total PHP old session files found | total=$total;;;;;"

if [ $total -lt ${NUMBER} ] ; then
    echo "OK: $msg"
    exit 0
else
    echo "WARNING: $msg"
    exit 1
fi
