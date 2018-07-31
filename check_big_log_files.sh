#!/bin/bash

SIZE="1G"

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

FIND_OPTS="${FIND_OPTS} ( -name *.log -o -name catalina.out ) -size +${SIZE} -print"

files=$(nice -n 19 find ${FIND_OPTS})

if [ -z "$files" ]; then
    echo "OK: No crazy log file found."
    exit 0
else
    if [ $(echo $files | wc -l) -eq 1 ]; then
        echo "WARNING: $files size is bigger than ${SIZE}iB."
    else
        echo "WARNING: $(echo $files | wc -l) log files are bigger than ${SIZE}iB."
    fi
    exit 1
fi
