#!/bin/bash

SIZE="1G"
CACHE=1 # days

CACHEFILE=/var/tmp/nagios/check_big_log_files
ERRFILE=/var/tmp/nagios/check_big_log_files.err

NAGIOS_USER=${SUDO_USER:-$(whoami)}
if ! [ -d "$(dirname "$CACHEFILE")" ]; then
    install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$CACHEFILE")"
fi

EXCLUDES="/var/cache /var/lib /usr/share /lost+found /proc /sys /dev /run"

while getopts "e:s:f" option; do
    case $option in
        e)
            EXCLUDES="${EXCLUDES} ${OPTARG}"
            ;;
        s)
            SIZE=${OPTARG}
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

if [ -f "$ERRFILE" ] && [ ! -O "$ERRFILE" ]; then
    echo "UNKNOWN: $ERRFILE is not owned by $USER"
    exit 3
fi

FIND_EXCLUDES=""

for EXCLUDE in ${EXCLUDES}; do
    FIND_EXCLUDES="${FIND_EXCLUDES} -path ${EXCLUDE} -prune -o"
done

FIND_OPTS="\\( -name '*.log' -o -name syslog -o -name catalina.out \\) -size +${SIZE} -print"

if [ -n "$(find $CACHEFILE -mtime -${CACHE} -print)" ]; then # If CACHEFILE exists and is less than 1day old
    if grep -q '^/' $CACHEFILE; then # If there is results in the file, check if they still exist
        ts=$(date -r $CACHEFILE) # We need to update the file without changing the date
        # shellcheck disable=SC2013
        files="$(for f in $(cat $CACHEFILE); do find "$f" -size +"${SIZE}" -print 2>/dev/null; done)"
        if [ -n "$files" ]; then
            echo -e "$files" > $CACHEFILE
        else
            truncate -s 0 $CACHEFILE
        fi
        touch -d "$ts" $CACHEFILE
    fi
else # Full scan with find
    # locate --regex '.*(\.log|syslog|catalina.out)$' | xargs -L1 du -sm | awk '$1>1000{print $2}' ?
    if ! LC_ALL=C eval "nice -n 10 find / ${FIND_EXCLUDES} ${FIND_OPTS}" > $CACHEFILE 2>$ERRFILE; then
        if grep -v 'No such device' "$ERRFILE"; then
            rm -f $CACHEFILE
            echo "UNKNOWN: error during find"
            exit 3
        fi
    fi
fi

num=$(grep -c '^/' $CACHEFILE) # grep avoids to count empty lines

if [ "$num" -eq 0 ]; then
    echo "OK: No crazy log file found."
    exit 0
elif [ "$num" -eq 1 ]; then
    echo "WARNING: $(cat $CACHEFILE) size is $(du -sh "$(cat $CACHEFILE)" | cut -f -1) (bigger than ${SIZE}iB)."
    exit 1
else
    echo "WARNING: $num log files are bigger than ${SIZE}iB. See /var/tmp/nagios/check_big_log_files"
    exit 1
fi
