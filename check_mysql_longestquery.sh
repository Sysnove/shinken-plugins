#!/bin/bash

### Usage: check_mysql_longestquery --warning 600 --critical 3600
### Needs to be run as root to see requests made by all users

usage () {
    sed -rn 's/^### ?//;T;p' "$0"
    echo "v$VERSION"
}

WARNING=600
CRITICAL=3600

while [ -n "$1" ]; do
    case $1 in
        --warning) shift; WARNING=$1 ;;
        --critical) shift; CRITICAL=$1 ;;
        -h) usage; exit 0;;
        *) usage; exit 1;;
    esac
    shift
done

# shellcheck disable=SC2086
running_count=$(($(mysql -sN -e "SELECT count(*) FROM INFORMATION_SCHEMA.PROCESSLIST;") - 1))
# shellcheck disable=SC2086
warning_count=$(mysql -sN -e "SELECT count(*) FROM INFORMATION_SCHEMA.PROCESSLIST where time > $WARNING;")
# shellcheck disable=SC2086
critical_count=$(mysql -sN -e "SELECT count(*) FROM INFORMATION_SCHEMA.PROCESSLIST where time > $CRITICAL;")
# shellcheck disable=SC2086
longest_running_query=$(mysql -sN -e "SELECT MAX(time) FROM INFORMATION_SCHEMA.PROCESSLIST")

# shellcheck disable=SC2181
if [ $? != 0 ]; then
    exit 3
fi

perfdata="running_queries=$running_count; warning_queries=$warning_count; critical_queries=$critical_count; longest_running_query=${longest_running_query}s;$WARNING;$CRITICAL"

if [ "$critical_count" -ge 1 ]; then
    echo "CRITICAL : $critical_count querie(s) running for longer than $CRITICAL seconds | $perfdata"
    exit 2
elif [ "$warning_count" -ge 1 ]; then
    echo "WARNING : $warning_count querie(s) running for longer than $WARNING seconds | $perfdata"
    exit 1
else
    echo "OK : $running_count running querie(s) | $perfdata"
fi
