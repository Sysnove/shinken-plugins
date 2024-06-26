#!/bin/bash

LOGS=

MIN_RATE=2

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

LAST_RUN_FILE=/var/tmp/nagios/check_web_logs_v2_last_run

NAGIOS_USER=${SUDO_USER:-$(whoami)}
if ! [ -d "$(dirname "$LAST_RUN_FILE")" ]; then
    install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$LAST_RUN_FILE")"
fi

# :COMMENT:maethor:20210121: Temporaire
if [ -f "${LAST_RUN_FILE/nagios\//}" ] && [ ! -f "$LAST_RUN_FILE" ]; then
    mv ${LAST_RUN_FILE/nagios\//} "$LAST_RUN_FILE"
fi

if [ -f "$LAST_RUN_FILE" ] && [ ! -O "$LAST_RUN_FILE" ]; then
    echo "UNKNOWN: $LAST_RUN_FILE is not owned by $USER"
    exit $E_UNKNOWN
fi

show_help() {
	echo "todo"
}


# process args
while [ -n "$1" ]; do 
    case $1 in
        -l)	shift; LOGS=$1 ;;
        -m) shift; MIN_RATE=$1 ;;
        -w3) shift; WARN_3=$1 ;;
        -w4) shift; WARN_4=$1 ;;
        -w5) shift; WARN_5=$1 ;;
        -c3) shift; CRIT_3=$1 ;;
        -c4) shift; CRIT_4=$1 ;;
        -c5) shift; CRIT_5=$1 ;;
        -t) shift; LAST_RUN_FILE=$1 ;;
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

log_files_readable=0
log_files_non_readable=0
for log in $LOGS; do
    if [ -r "$log" ]; then
        log_files_readable=$((log_files_readable + 1))
    else
        log_files_non_readable=$((log_files_non_readable + 1))
    fi
done

if [ $log_files_readable = 0 ]; then
    echo "UNKNOWN - No readable log file in $LOGS"
    if [ "$LOGS" == "/var/log/docker/docker/base_traefik.log" ]; then
        exit 0
    else
        exit 3
    fi
fi


old_count2=-1
old_count3=-1
old_count4=-1
old_count499=-1
old_count5=-1
old_countall=-1
last_check=-1
# shellcheck disable=SC1090
source "$LAST_RUN_FILE"

new_count2=0
new_count3=0
new_count4=0
new_count499=0
new_count5=0
# shellcheck disable=SC2086
new_countall=$(wc -l $LOGS | tail -n 1 | awk '{print $1}')
now=$(date +%H:%M:%S)

IFS=$'\n'
# shellcheck disable=SC2086
for line in $(grep -v 'check_websites_security' $LOGS | grep -o '" [2-5].. ' | cut -d ' ' -f 2 | sort | uniq -c); do
    code=$(echo $line | awk '{print $2}')
    count=$(echo $line | awk '{print $1}')
    if [[ "$code" == 2* ]]; then
        new_count2=$((new_count2 + count))
    elif [[ "$code" == 3* ]]; then
        new_count3=$((new_count3 + count))
    elif [[ "$code" == 4* ]]; then
        new_count4=$((new_count4 + count))
        if [ $code -eq 499 ]; then
            count499=$((new_count499 + count))
        fi
    elif [[ "$code" == 5* ]]; then
        new_count5=$((new_count5 + count))
    fi
done

echo "
old_count2=$new_count2
old_count3=$new_count3
old_count4=$new_count4
old_count499=$new_count499
old_count5=$new_count5
old_countall=$new_countall
last_check=$now
" > "$LAST_RUN_FILE"

if [ "$new_countall" -lt $old_countall ] ; then
    echo "UNKNOWN - Logs seem to have shrink since last run, please run the check again."
    exit 3
fi

if [ "$old_countall" == -1 ] ||
    [ "$old_count2" == -1 ] ||
    [ "$old_count3" == -1 ] ||
    [ "$old_count4" == -1 ] ||
    [ "$old_count499" == -1 ] ||
    [ "$old_count5" == -1 ] ; then
    echo "UNKNOWN - Variables missing in database, please run the check again."
    exit 3
fi

count2=$((new_count2 - old_count2))
count3=$((new_count3 - old_count3))
count4=$((new_count4 - old_count4))
count499=$((new_count499 - old_count499))
count5=$((new_count5 - old_count5))
countall=$((new_countall - old_countall))

pourcent2=0
pourcent3=0
pourcent4=0
pourcent499=0
pourcent5=0

if [ "$countall" -gt 0 ] ; then
    pourcent2=$(((count2 * 100) / countall))
    pourcent3=$(((count3 * 100) / countall))
    pourcent4=$(((count4 * 100) / countall))
    pourcent499=$(((count499 * 100) / countall))
    pourcent5=$(((count5 * 100) / countall))
fi

now_s=$(date -d "$now" +%s)
last_check_s=$(date -d "$last_check" +%s)
period=$(( now_s - last_check_s ))

ratetotal=$(bc <<< "scale=1; $countall / $period")

if [ $log_files_non_readable -gt 0 ]; then
    log_files_read_str="($log_files_readable log files read, $log_files_non_readable not readable)"
else
    log_files_read_str="($log_files_readable log files)"
fi

RET_MSG="$countall requests in $period seconds : $count2 2xx ($pourcent2%), $count3 3xx ($pourcent3%), $count4 4xx ($pourcent4%), $count5 5xx ($pourcent5%) $log_files_read_str | total=${ratetotal}req_per_sec;;;0;100 2xx=${pourcent2}%;;;0;100 3xx=${pourcent3}%;$WARN_3;$CRIT_3;0;100 4xx=${pourcent4}%;$WARN_4;$CRIT_4;0;100 499=${pourcent499}%;$WARN_5;$CRIT_5;0;100 5xx=${pourcent5}%;$WARN_5;$CRIT_5;0;100"

# :COMMENT:maethor:20210603:  499 errors are check with 5** threshold. May not be a good idea, we'll see
if [ "$MIN_RATE" -gt "$ratetotal" ]; then
    if [ $pourcent3 -gt "$CRIT_3" ] || [ $pourcent4 -gt "$CRIT_4" ] || [ $pourcent5 -gt "$CRIT_5" ] || [ $pourcent499 -gt "$CRIT_5" ]; then
        RET_MSG="CRITICAL - $RET_MSG"
        RET_CODE=$E_CRITICAL
    elif [ $pourcent3 -gt "$WARN_3" ] || [ $pourcent4 -gt "$WARN_4" ] || [ $pourcent5 -gt "$WARN_5" ] || [ $pourcent499 -gt "$WARN_5" ]; then
        RET_MSG="WARNING - $RET_MSG"
        RET_CODE=$E_WARNING
    else
        RET_MSG="OK - $RET_MSG"
        RET_CODE=$E_OK
    fi
else
    RET_MSG="OK - $RET_MSG"
    RET_CODE=$E_OK
fi

echo "$RET_MSG"
exit "$RET_CODE"
