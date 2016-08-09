#!/bin/bash

# Must be ran by root
if [ "${USER}" != "root" ]; then
    sudo $0 $*
    exit $?
fi

EXIT_OK=0
EXIT_WARNING=1
EXIT_CRITICAL=2

usage(){
    cat <<OEF
Usage:
    $0 directory critical_threshold [warning_threshold]

    directory:          Directory to check.
    critical_threshold: Number of days to raise critical when no file found for.
    warning_threshold:  Number of days to raise warning xhen no file found for.
                        Ignored if greater than critical threshold.
OEF
    exit ${EXIT_CRITICAL}
}

if [ $# -ne 2 -a $# -ne 3 ]; then
    echo "CRITICAL: $# parameters passed but 2 or 3 are required."
    usage
fi

BASE_DIR="$1"

if [ ! -d "${BASE_DIR}" -o ! -r "${BASE_DIR}" ]; then
    echo "CRITICAL: ${BASE_DIR} is not a readable directory."
    exit ${EXIT_CRITICAL}
fi

re='^[0-9]+$'

CRITICAL_THRESHOLD="$2"

if [[ ! "${CRITICAL_THRESHOLD}" =~ $re ]]; then
    echo "CRITICAL: Critical threshold must be a positive integer."
    exit ${EXIT_CRITICAL}
fi

WARNING_THRESHOLD="$3"

[ -n "${WARNING_THRESHOLD}" ] && if [[ ! "${WARNING_THRESHOLD}" =~ $re ]]; then
    echo "CRITICAL: Warning threshold must be a positive integer."
    exit ${EXIT_CRITICAL}
fi

BASE_FIND_COMMAND="find ${BASE_DIR} -type f ! -empty"

CRITICAL_CHECK=$(${BASE_FIND_COMMAND} -ctime -3 | wc -l)

if [ ${CRITICAL_CHECK} -eq ${CRITICAL_THRESHOLD} ]; then
    echo "CRITICAL: No backup files found in ${BASE_DIR} for the last ${CRITICAL_THRESHOLD} day(s)."
    exit ${EXIT_CRITICAL}
fi

[ -n "${WARNING_THRESHOLD}" ] && if [ "${WARNING_THRESHOLD}" -lt ${CRITICAL_THRESHOLD} ]; then
    WARNING_CHECK=$(${BASE_FIND_COMMAND} -ctime -1 | wc -l)

    if [ ${WARNING_CHECK} -eq ${WARNING_THRESHOLD} ]; then
        echo "WARNING: No files found in ${BASE_DIR} for the last ${WARNING_THRESHOLD} day(s)."
        exit ${EXIT_WARNING}
    fi

    echo "OK: Found ${WARNING_CHECK} file(s) in ${BASE_DIR} for the last ${WARNING_THRESHOLD} day(s)."
    exit ${EXIT_OK}
fi

echo "OK: Found ${CRITICAL_CHECK} file(s) in ${BASE_DIR} for the last ${CRITICAL_THRESHOLD} day(s)."
exit ${EXIT_OK}
