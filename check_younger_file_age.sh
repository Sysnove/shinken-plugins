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

critical() {
	echo "CRITICAL - $*"
	exit ${CRIT}
}

warning() {
	echo "WARNING - $*"
	exit ${WARN}
}

ok() {
	echo "OK - $*"
	exit ${OK}
}

unknown() {
	echo "UNKNOWN - $*"
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


THRESHOLD=${CRIT_THRESHOLD}

NB=$(find "${DIRECTORY}" -mmin -$((THRESHOLD * 60)) -type f -ls | wc -l)

[[ "${NB}" -eq 0 ]] && critical "No file younger than ${THRESHOLD} hours."

if [ "${WARN_THRESHOLD}" -le "${CRIT_THRESHOLD}" ]; then
    THRESHOLD=${WARN_THRESHOLD}

    NB=$(find "${DIRECTORY}" -mmin -$((THRESHOLD * 60)) -type f -ls | wc -l)

    [[ "${NB}" -eq 0 ]] && warning "No file younger than ${THRESHOLD} hours."
fi

ok "${NB} files found younger than ${THRESHOLD} hours."
