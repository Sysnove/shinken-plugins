#!/bin/bash

OK=0
WARN=1
CRIT=2
UNKN=3

usage() {
    cat <<EOF
Usage: $0 [options] -d PATH

Checks a directory to find if there is at least one file younger than thresholds.

    -w WARNING  Warning threshold in hours (defaults to 7)
    -c CRITICAL Critical threshold in hours (defaults to 13)
    -d PATH     Path of the directory to check
EOF
    exit ${UNKN}
}

WARN_THRESHOLD=7
CRIT_THRESHOLD=13

while getopts "w:c:d:" option
do
    case ${option} in
        w)
            WARN_THRESHOLD=${OPTARG}
            ;;
        c)
            CRIT_THRESHOLD=${OPTARG}
            ;;
        d)
            DIRECTORY=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done

[ -z "$DIRECTORY" ] && usage

# head makes find quit after first file found and speed up script
if [ -z "$(find "$DIRECTORY" -mmin -$((WARN_THRESHOLD * 60)) -type f | grep -v README | head -n 1)" ]; then
    if [ -z "$(find "$DIRECTORY" -mmin -$((CRIT_THRESHOLD * 60)) -type f | grep -v README | head -n 1)" ]; then
        echo "CRITICAL - No file younger than $CRIT_THRESHOLD hours in $DIRECTORY."
        exit $CRIT
    fi
    echo "WARNING - No file younger than $WARN_THRESHOLD hours in $DIRECTORY."
    exit $WARN
fi

echo "OK - There is at least one files younger than $WARN_THRESHOLD hours in $DIRECTORY."
exit $OK
