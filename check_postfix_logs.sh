#!/bin/bash

###
### This plugin checks /var/log/mail.log
### Thresholds allow to detect usual email sendings
###
### CopyLeft 2021 Guillaume Subiron <guillaume@sysnove.fr>
###
### Usage : check_postfix_logs.sh -w 

usage() {
     sed -rn 's/^### ?//;T;p' "$0"
}

OUT_SENT_WARN=60
OUT_DEFERRED_WARN=60
OUT_BOUNCED_WARN=60
OUT_SENT_CRIT=120
OUT_DEFERRED_CRIT=120
OUT_BOUNCED_CRIT=120
DATEFORMAT=rsyslog

while [ -n "$1" ]; do
    case $1 in
        --out-sent-warn) shift; OUT_SENT_WARN=$1 ;;
        --out-deferred-warn) shift; OUT_DEFERRED_WARN=$1 ;;
        --out-bounced-warn) shift; OUT_BOUNCED_WARN=$1 ;;
        --out-sent-crit) shift; OUT_SENT_CRIT=$1 ;;
        --out-deferred-crit) shift; OUT_DEFERRED_CRIT=$1 ;;
        --out-bounced-crit) shift; OUT_BOUNCED_CRIT=$1 ;;
        --iso) DATEFORMAT="%O" ;;
        -h) usage; exit 0 ;;
    esac
    shift
done

LOG_FILE="/var/log/mail.log"

E_OK=0
E_WARNING=1
E_CRITICAL=2
E_UNKNOWN=3

LAST_RUN_FILE=/var/tmp/nagios/check_mail_logs_last_run

NAGIOS_USER=${SUDO_USER:-$(whoami)}
if ! [ -d "$(dirname "$LAST_RUN_FILE")" ]; then
    install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$LAST_RUN_FILE")"
fi

if [ -f "$LAST_RUN_FILE" ] && [ ! -O "$LAST_RUN_FILE" ]; then
    echo "UNKNOWN: $LAST_RUN_FILE is not owned by $USER"
    exit $E_UNKNOWN
fi

function compute() {
    echo "$1" | bc -l | awk '{printf "%.1f", $0}'
}

# check logs
if [ -z "$LOG_FILE" ]; then
    echo "File(s) not found : $LOG_FILE"
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

/usr/local/bin/dategrep -format "${DATEFORMAT}" --start "$since" "$LOG_FILE" | grep ' postfix/'  > $tmpfile

tmpfile_in="/tmp/$$_in.tmp"

tmpfile_out="/tmp/$$_out.tmp"

# Outgoing
grep 'postfix/smtp\[' $tmpfile | grep -E -v 'relay=[^ \[]*\[127\.0\.0\.1\]'> $tmpfile_out

out_bounced=$(grep 'status=bounced' -c $tmpfile_out)
out_deferred=$(grep 'status=deferred' -c $tmpfile_out)
out_sent=$(grep 'status=sent' -c $tmpfile_out)

# Incoming
grep -E 'postfix/(pipe|cleanup)\[' $tmpfile > $tmpfile_in

in_accepted=$(grep 'status=sent' -c $tmpfile_in)
in_virus=$(grep 'Infected' -c $tmpfile_in)
in_spam=$(grep 'Spam message rejected' -c $tmpfile_in)
in_ratelimit=$(grep 'Rate limit exceeded' -c $tmpfile_in)
in_greylist=$(grep 'Try again later' -c $tmpfile_in)
in_reject=$(grep postfix/smtpd | grep 'NOQUEUE: reject' -c $tmpfile)

now_s=$(date -d "$now" +%s)
since_s=$(date -d "$since" +%s)
period=$(( now_s - since_s ))

rate_out_bounced=$(compute "$out_bounced * 60 / $period")
rate_out_deferred=$(compute "$out_deferred * 60 / $period")
rate_out_sent=$(compute "$out_sent * 60 / $period")

rate_in_accepted=$(compute "$in_accepted * 60 / $period")
rate_in_virus=$(compute "$in_virus * 60 / $period")
rate_in_spam=$(compute "$in_spam * 60 / $period")
rate_in_ratelimit=$(compute "$in_ratelimit * 60 / $period")
rate_in_greylist=$(compute "$in_greylist * 60 / $period")
rate_in_reject=$(compute "$in_reject * 60 / $period")

PERFDATA="o_sent=$rate_out_sent;$OUT_SENT_WARN;$OUT_SENT_CRIT;0; o_bounced=$rate_out_bounced;$OUT_BOUNCED_WARN;$OUT_BOUNCED_CRIT;0; o_deferred=$rate_out_deferred;$OUT_DEFERRED_WARN;$OUT_DEFERRED_CRIT;0; i_accepted=$rate_in_accepted; i_virus=$rate_in_virus; i_spam=$rate_in_spam; i_ratelimit=$rate_in_ratelimit; i_greylist=$rate_in_greylist; i_reject=$rate_in_reject;"

RET_MSG="$in_accepted messages received and $out_sent messages sent in the last $period seconds | $PERFDATA"

if (( $(echo "$rate_out_sent > $OUT_SENT_CRIT" | bc -l) )) || (( $(echo "$rate_out_deferred > $OUT_DEFERRED_CRIT" | bc -l) )) || (( $(echo "$rate_out_bounced > $OUT_BOUNCED_CRIT" | bc -l) )); then
    RET_CODE=$E_CRITICAL
    RET_MSG="CRITICAL - $RET_MSG"
elif (( $(echo "$rate_out_sent > $OUT_SENT_WARN" | bc -l) )) || (( $(echo "$rate_out_deferred > $OUT_DEFERRED_WARN" | bc -l) )) || (( $(echo "$rate_out_bounced > $OUT_BOUNCED_WARN" | bc -l) )); then
    RET_CODE=$E_WARNING
    RET_MSG="WARNING - $RET_MSG"
else
    RET_CODE=$E_OK
    RET_MSG="OK - $RET_MSG"
fi


if grep -E -q 'warning: database .* is older than source file' $tmpfile; then
    RET_MSG="WARNING - Old postfix database file - $RET_MSG"
    RET_CODE=$E_WARNING
fi

rm $tmpfile
rm $tmpfile_in
rm $tmpfile_out

echo "$RET_MSG"
exit $RET_CODE
