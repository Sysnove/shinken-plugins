#!/bin/bash

TMPFILE=/var/tmp/check_php_sessions
CACHE=1 # days

if [ -d /usr/local/ispconfig ] ; then
    NUMBER=30000
else
    NUMBER=10000
fi

AGE=16
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
FIND_OPTS="${FIND_OPTS} -regextype posix-egrep -regex '.*/(ci_session|sess_).*' -ctime +${AGE} -print"

if ! [[ $(find $TMPFILE -mtime -${CACHE} -print 2>/dev/null) ]]; then
    nice -n 10 find ${FIND_OPTS} 2>/dev/null > $TMPFILE
    files="$(cat $TMPFILE)"
else
    files="$(cat $TMPFILE | xargs sudo ls -d 2>/dev/null)"
    echo "$files" > $TMPFILE
fi

if $LIST; then
    echo $files
else
    total=$(echo $files |wc -l)

    msg="$total PHP old session files found | total=$total;;;;;"

    if [ $total -lt ${NUMBER} ] ; then
        echo "OK: $msg"
        exit 0
    else
        echo "WARNING: $msg"
        exit 1
    fi
fi
