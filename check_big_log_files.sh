#!/bin/bash

SIZE="1G"
CACHE=1 # days

CACHEFILE=/var/tmp/check_big_log_files

while getopts "e:s:" option; do
    case $option in
        e)
            EXCLUDES="${EXCLUDES} ${OPTARG}"
            ;;
        s)
            SIZE=${OPTARG}
            ;;
    esac
done

FIND_OPTS='/'

for EXCLUDE in ${EXCLUDES}; do
    FIND_OPTS="${FIND_OPTS} -path ${EXCLUDE} -prune -o"
done

FIND_OPTS="${FIND_OPTS} ( -name *.log -o -name syslog -o -name catalina.out ) -size +${SIZE} -print"

if ! [[ $(find $CACHEFILE -mtime -${CACHE} -print 2>/dev/null) ]]; then
    nice -n 10 find ${FIND_OPTS} > $CACHEFILE
else
    files="$(for f in $(cat $CACHEFILE); do find $f -size +${SIZE} -print; done)"
    echo "$files" > $CACHEFILE
fi

num=$(wc -l $CACHEFILE)

if [ $num -eq 0 ]; then
    echo "OK: No crazy log file found."
    exit 0
elif [ $num -eq 1 ]; then
    echo "WARNING: $(cat $CACHEFILE) size is bigger than ${SIZE}iB."
    exit 1
else
    echo "WARNING: $num log files are bigger than ${SIZE}iB."
    exit 1
fi
