#!/bin/bash

CACHEFILE=/var/tmp/nagios/check_php_sessions
CACHE=1 # days

NAGIOS_USER=${SUDO_USER:-$(whoami)}
if ! [ -d "$(dirname "$CACHEFILE")" ]; then
    install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$CACHEFILE")"
fi

if [ -d /usr/local/ispconfig ] ; then
    THRESHOLD=30000
else
    THRESHOLD=10000
fi

AGE=16
LIST=false

EXCLUDES="/var/cache /var/lib /usr/share /lost+found /proc /sys /dev /run"

while getopts "e:n:a:Lf" option; do
    case $option in
        e)
            EXCLUDES="${EXCLUDES} ${OPTARG}"
            ;;
        n)
            THRESHOLD=${OPTARG}
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
    FIND_EXCLUDES="${FIND_EXCLUDES} -path ${EXCLUDE} -prune -o"
done

FIND_OPTS="-regextype posix-egrep -regex '.*/(ci_session|sess_).*' -ctime +${AGE} -print"

if [ -z "$(find $CACHEFILE -mtime -${CACHE} -print)" ]; then
    if ! eval "nice -n 10 find / ${FIND_EXCLUDES} ${FIND_OPTS}" > $CACHEFILE; then
        rm -f $CACHEFILE
        echo "UNKNOWN: error during find"
        exit 3
    fi
    if [ -d /var/lib/php/sessions ]; then
        if ! eval "nice -n 10 find /var/lib/php/sessions ${FIND_OPTS}" >> $CACHEFILE; then
            rm $CACHEFILE
            echo "UNKNOWN: error during second find"
            exit 3
        fi
    fi
else
    if grep -q '^/' $CACHEFILE; then
        # shellcheck disable=SC2013
        files=$(cat $CACHEFILE | xargs ls -d 2>/dev/null)
        if [ -n "$files" ]; then
            echo -e "$files" > $CACHEFILE
        else
            truncate -s 0 $CACHEFILE
        fi
    fi
fi

if $LIST; then
    cat $CACHEFILE
else
    total=$(grep -c '^/' $CACHEFILE) # grep avoids to count empty lines
    msg="$total PHP old session files found | total=$total;;;;;"

    if [ "$total" -lt "${THRESHOLD}" ] ; then
        echo "OK: $msg"
        exit 0
    else
        echo "WARNING: $msg"
        exit 1
    fi
fi
