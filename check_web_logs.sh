#!/bin/bash

LOGS=
WARN_3=100
WARN_4=100
WARN_5=100
CRIT_3=100
CRIT_4=100
CRIT_5=100

E_OK=0
E_WARNING=1
E_CRITICAL=2
E_UNKNOWN=3

LAST_RUN_FILE=/var/tmp/check_web_logs_last_run

show_help() {
	echo "todo"
}


# process args
while [ ! -z "$1" ]; do 
    case $1 in
        -l)	shift; LOGS_WITH_GLOB=$1 ;;
        -w3) shift; WARN_3=$1 ;;
        -w4) shift; WARN_4=$1 ;;
        -w5) shift; WARN_5=$1 ;;
        -c3) shift; CRIT_3=$1 ;;
        -c4) shift; CRIT_4=$1 ;;
        -c5) shift; CRIT_5=$1 ;;
        -h)	show_help; exit 1 ;;
    esac
    shift
done

# check args
if [ -z "$LOGS_WITH_GLOB" ]; then
	echo "Need log files"
    show_help
    exit $E_UNKNOWN
fi

LOGS=$(ls $LOGS_WITH_GLOB 2>/dev/null)

# check logs
if [ -z "$LOGS" ]; then
    echo "File(s) not found : $LOGS_WITH_GLOB"
    exit $E_UNKNOWN
fi

# find last check
if [ ! -f $LAST_RUN_FILE ]; then
    echo "$(date +%R -d '5 min ago')" > $LAST_RUN_FILE
fi

since=$(<$LAST_RUN_FILE)
now=$(date +%R)

echo "$now" > $LAST_RUN_FILE

$tmpfile="/tmp/$$.tmp"

/usr/local/bin/dategrep --sort-files -format apache --start $since $LOGS > $tmpfile

total=$(wc -l $tmpfile)
count2=$(cat $tmpfile | cut -d ' ' -f 9 | grep '2..' -c)
count3=$(cat $tmpfile | cut -d ' ' -f 9 | grep '3..' -c)
count4=$(cat $tmpfile | cut -d ' ' -f 9 | grep '4..' -c)
count5=$(cat $tmpfile | cut -d ' ' -f 9 | grep '5..' -c)

rm $tmpfile

pourcent2=0
pourcent3=0
pourcent4=0
pourcent5=0

if [ $total -gt 0 ] ; then
    pourcent2=$((($count2 * 100) / $total))
    pourcent3=$((($count3 * 100) / $total))
    pourcent4=$((($count4 * 100) / $total))
    pourcent5=$((($count5 * 100) / $total))
fi

now_s=$(date -d $now +%s)
since_s=$(date -d $since +%s)
period=$(( $now_s - $since_s ))

ratetotal=$(($total / $period))
rate2=$(($count2 / $period))
rate3=$(($count3 / $period))
rate4=$(($count4 / $period))
rate5=$(($count5 / $period))

RET_MSG="$total requests in $period seconds : $count2 2xx ($pourcent2%), $count3 3xx ($pourcent3%), $count4 4xx ($pourcent4%), $count5 5xx ($pourcent5%) | total=$total;;;;0;100 2xx=$rate2;;;;0;100 3xx=$rate3;;;;0;100 4xx=$rate4;;;;0;100 5xx=$rate5;;;;0;100"

if [ $pourcent3 -gt $WARN_3 -o $pourcent4 -gt $WARN_4 -o $pourcent4 -gt $WARN_4 -o $pourcent5 -gt $WARN_5 ]; then
    if [ $pourcent3 -gt $CRIT_3 -o $pourcent4 -gt $CRIT_4 -o $pourcent5 -gt $CRIT_5 ]; then
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
