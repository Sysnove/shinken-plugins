#!/bin/bash

SIZE="1G"
CACHE=1 # days

CACHEFILE=/var/tmp/nagios/check_big_log_files

NAGIOS_USER=${SUDO_USER:-$(whoami)}
install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$CACHEFILE")"

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

FIND_EXCLUDES=""

for EXCLUDE in ${EXCLUDES}; do
    FIND_EXCLUDES="${FIND_EXCLUDES} -path ${EXCLUDE} -prune -o"
done

FIND_OPTS="\\( -name '*.log' -o -name syslog -o -name catalina.out \\) -size +${SIZE} -print"

if ! find $CACHEFILE -mtime -${CACHE} -print > /dev/null 2>&1; then
    if ! eval "nice -n 10 find / ${FIND_EXCLUDES} ${FIND_OPTS}" > $CACHEFILE; then
        rm -f $CACHEFILE
        echo "UNKNOWN: error during find"
        exit 3
    fi
else
    if [ -s "$CACHEFILE" ]; then
        # shellcheck disable=SC2013
        files="$(for f in $(cat $CACHEFILE); do find "$f" -size +"${SIZE}" -print; done)"
        echo -n "$files" > $CACHEFILE
    fi
fi

num=$(wc -l < $CACHEFILE)

if [ "$num" -eq 0 ]; then
    echo "OK: No crazy log file found."
    exit 0
elif [ "$num" -eq 1 ]; then
    echo "WARNING: $(cat $CACHEFILE) size is $(du -sh "$(cat $CACHEFILE)" | cut -f -1) (bigger than ${SIZE}iB)."
    exit 1
else
    echo "WARNING: $num log files are bigger than ${SIZE}iB."
    exit 1
fi
