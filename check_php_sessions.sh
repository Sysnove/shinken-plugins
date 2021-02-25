#!/bin/bash

CACHEFILE=/var/tmp/nagios/check_php_sessions
CACHE=1 # days

NAGIOS_USER=${SUDO_USER:-$(whoami)}
install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$CACHEFILE")"

if [ -d /usr/local/ispconfig ] ; then
    NUMBER=30000
else
    NUMBER=10000
fi

AGE=16
LIST=false

EXCLUDES="/var/cache /var/lib /usr/share /proc /sys"

while getopts "e:n:a:Lf" option; do
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
        f)
            rm -f "$CACHEFILE"
            ;;
        *)
    esac
done

if [ -f "$CACHEFILE" ] && [ ! -O "$CACHEFILE" ]; then
    echo "UNKNOWN: $CACHEFILE is not owned by $USER"
    exit 3
fi


FIND_EXCLUDES=""

for EXCLUDE in ${EXCLUDES}; do
    FIND_EXCLUDES="${FIND_OPTS} -path ${EXCLUDE} -prune -o"
done

FIND_OPTS="-regextype posix-egrep -regex '.*/(ci_session|sess_).*' -ctime +${AGE} -print"

if ! find $CACHEFILE -mtime -${CACHE} -print 2>/dev/null > /dev/null; then
    eval "nice -n 10 find / ${FIND_EXCLUDES} ${FIND_OPTS}" > $CACHEFILE
    if [ $? -gt 1 ]; then
        rm $CACHEFILE
        echo "UNKNOWN: error during first find"
        exit 3
    fi
    eval "nice -n 10 find /var/lib/php/sessions ${FIND_OPTS}" >> $CACHEFILE
    if [ $? -gt 1 ]; then
        rm $CACHEFILE
        echo "UNKNOWN: error during second find"
        exit 3
    fi
else
    if ! [ -s "$CACHEFILE" ]; then
        # shellcheck disable=SC2002
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
