#!/bin/bash

if [ -d /usr/local/ispconfig ] ; then
    NUMBER=30000
else
    NUMBER=10000
fi

AGE=15
LIST=false

while getopts "e:n:a:L" option; do
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
        L)
            LIST=true
    esac
done

FIND_OPTS='/'

for EXCLUDE in ${EXCLUDES}; do
    FIND_OPTS="${FIND_OPTS} -path ${EXCLUDE} -prune -o"
done

FIND_OPTS="${FIND_OPTS} -path /usr/share -prune -o"
FIND_OPTS="${FIND_OPTS} -regextype posix-egrep -regex .*/(ci_session|sess_).* -ctime +${AGE} -print"

if $LIST; then
    nice -n 19 find ${FIND_OPTS} 2>/dev/null
else
    total=$(nice -n 19 find ${FIND_OPTS} 2>/dev/null | wc -l)

    msg="$total PHP old session files found | total=$total;;;;;"

    if [ $total -lt ${NUMBER} ] ; then
        echo "OK: $msg"
        exit 0
    else
        echo "WARNING: $msg"
        exit 1
    fi
fi
