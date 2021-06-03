#!/bin/bash

LOGS=

MIN=2

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

LAST_RUN_FILE=/var/tmp/nagios/check_web_logs_last_run

NAGIOS_USER=${SUDO_USER:-$(whoami)}
install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$LAST_RUN_FILE")"

# :COMMENT:maethor:20210121: Temporaire
if [ -f "${LAST_RUN_FILE/nagios\//}" ] && [ ! -f "$LAST_RUN_FILE" ]; then
    mv ${LAST_RUN_FILE/nagios\//} "$LAST_RUN_FILE"
fi

if [ -f "$LAST_RUN_FILE" ] && [ ! -O "$LAST_RUN_FILE" ]; then
    echo "UNKNOWN: $LAST_RUN_FILE is not owned by $USER"
    exit 3
fi

show_help() {
	echo "todo"
}


# process args
while [ -n "$1" ]; do 
    case $1 in
        -l)	shift; LOGS=$1 ;;
        -m) shift; MIN=$1 ;;
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
if [ -z "$LOGS" ]; then
	echo "Need log files"
    show_help
    exit $E_UNKNOWN
fi

# find last check
if [ ! -f $LAST_RUN_FILE ]; then
    date +%H:%M:%S -d '5 min ago' > $LAST_RUN_FILE
fi

since=$(<$LAST_RUN_FILE)
now=$(date +%H:%M:%S)

echo "$now" > $LAST_RUN_FILE

tmpfile="/tmp/$$.tmp"
touch $tmpfile

#/usr/local/bin/dategrep --sort-files -format apache --start "$since" "$LOGS" | grep -v check_http | grep -E -o '" [0-9]{3} ' | cut -d ' ' -f 2 > $tmpfile
for log in $LOGS; do
    if [ ! -r "$log" ]; then
        echo "UNKNOWN : $log is not readable."
        exit 3
    fi
    (/usr/local/bin/dategrep -format apache --start "$since" "$log" || exit 3) | grep -v check_http | grep -E -o '" [0-9]{3} ' | cut -d ' ' -f 2 >> $tmpfile
done

total=$(wc -l < $tmpfile)

count2=$(grep '2..' -c $tmpfile)
count3=$(grep '3..' -c $tmpfile)
count4=$(grep '4..' -c $tmpfile)
count5=$(grep '5..' -c $tmpfile)

rm $tmpfile

pourcent2=0
pourcent3=0
pourcent4=0
pourcent5=0

if [ "$total" -gt 0 ] ; then
    pourcent2=$(((count2 * 100) / total))
    pourcent3=$(((count3 * 100) / total))
    pourcent4=$(((count4 * 100) / total))
    pourcent5=$(((count5 * 100) / total))
fi

now_s=$(date -d "$now" +%s)
since_s=$(date -d "$since" +%s)
period=$(( now_s - since_s ))

ratetotal=$(bc <<< "scale=1; $total / $period")
#rate2=$((count2 / period))
#rate3=$((count3 / period))
#rate4=$((count4 / period))
#rate5=$((count5 / period))

RET_MSG="$total requests in $period seconds : $count2 2xx ($pourcent2%), $count3 3xx ($pourcent3%), $count4 4xx ($pourcent4%), $count5 5xx ($pourcent5%) | total=${ratetotal}req_per_sec;;;0;100 2xx=${pourcent2}%;;;0;100 3xx=${pourcent3}%;$WARN_3;$CRIT_3;0;100 4xx=${pourcent4}%;$WARN_4;$CRIT_4;0;100 5xx=${pourcent5}%;$WARN_5;$CRIT_5;0;100"

if [[ ($pourcent3 -gt $WARN_3 && $count3 -ge $MIN) || ($pourcent4 -gt $WARN_4 && $count4 -ge $MIN) || ($pourcent5 -gt $WARN_5 && $count5 -ge $MIN) ]]; then
    if [[ $pourcent3 -gt $CRIT_3 || $pourcent4 -gt $CRIT_4 || $pourcent5 -gt $CRIT_5 ]]; then
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

echo "$RET_MSG"
exit $RET_CODE
