#!/bin/bash

CACHEFILE=/var/tmp/nagios/check_php_sessions
CACHE=1 # days

install -g nagios -o nagios -m 750 -d "$(dirname $CACHEFILE)"

# :COMMENT:maethor:20210121: Temporaire
if [ -f "${CACHEFILE/nagios\//}" ] && [ ! -f "$CACHEFILE" ]; then
    mv ${CACHEFILE/nagios\//} "$CACHEFILE"
fi

if [ -f "$CACHEFILE" ] && [ ! -O "$CACHEFILE" ]; then
    echo "UNKNOWN: $CACHEFILE is not owned by $USER"
    exit 3
fi

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
            ;;
        *)
    esac
done

FIND_OPTS='/'

for EXCLUDE in ${EXCLUDES}; do
    FIND_OPTS="${FIND_OPTS} -path ${EXCLUDE} -prune -o"
done

FIND_OPTS="${FIND_OPTS} -path /usr/share -prune -o"
FIND_OPTS="${FIND_OPTS} -regextype posix-egrep -regex .*/(ci_session|sess_).* -ctime +${AGE} -print"

if ! [[ $(find $CACHEFILE -mtime -${CACHE} -print 2>/dev/null) ]]; then
    nice -n 10 find "${FIND_OPTS}" 2>/dev/null > $CACHEFILE
else
    if [ "$(wc -l < $CACHEFILE)" -gt 0 ]; then
        # shellcheck disable=SC2013
        files=$(cat $CACHEFILE | xargs ls -d 2>/dev/null)
        echo "$files" > $CACHEFILE
    fi
fi

if $LIST; then
    cat $CACHEFILE
else
    total=$(wc -l < $CACHEFILE)

    msg="$total PHP old session files found | total=$total;;;;;"

    if [ "$total" -lt "${NUMBER}" ] ; then
        echo "OK: $msg"
        exit 0
    else
        echo "WARNING: $msg"
        exit 1
    fi
fi
