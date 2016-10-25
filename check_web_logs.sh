#!/bin/bash

LOGS=
WARN_404=100
WARN_50x=100
CRIT_404=100
CRIT_50x=100

E_OK=0
E_WARNING=1
E_CRITICAL=2
E_UNKNOWN=3

show_help() {
	echo "todo"
}

# process args
while [ ! -z "$1" ]; do 
    case $1 in
        -l)	shift; LOGS=$1 ;;
        -W) shift; WARN_50x=$1 ;;
        -w) shift; WARN_404=$1 ;;
        -C) shift; CRIT_50x=$1 ;;
        -c) shift; CRIT_404=$1 ;;
        -h)	show_help; exit 1 ;;
    esac
    shift
done

# check args
if [ -z "$LOGS" ]; then
	echo "Need log files"
    show_help
exit $E_UNKNOWN
fi

total=$(cat $LOGS | grep "" -c)

e404=$(cat $LOGS | cut -d ' ' -f 9 | grep '404' -c)
e50x=$(cat $LOGS | cut -d ' ' -f 9 | grep '50.' -c)

# :TODO:maethor:161022: if $total > 0
pourcent404=$((($e404 * 100) / $total))
pourcent50x=$((($e50x * 100) / $total))

RET_MSG="$total requests, $e404 404 ($pourcent404%), $e50x 50x ($pourcent50x%)"

if [ $pourcent404 -gt $WARN_404 -o $pourcent50x -gt $WARN_50x ]; then
    if [ $pourcent404 -gt $CRIT_404 -o $pourcent50x -gt $CRIT_50x ]; then
        RET_MSG="CRITICAL - $RET_MSG"
        RET_CODE=$E_CRITICAL
    else
        RET_MSG="WARNING - $RET_MSG"
        RET_CODE=$E_WARNING
    fi
else
    RET_MSG="OK - $RET_MSG"
    RET_CODE=$E_OK
fi

echo $RET_MSG
exit $RET_CODE
