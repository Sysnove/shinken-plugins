#!/bin/bash

# TODO Manage Amavis filtering. Currently this script manages only rmilter.

LOG_FILE="/var/log/mail.log"

E_OK=0
E_WARNING=1
E_CRITICAL=2
E_UNKNOWN=3

LAST_RUN_FILE=/var/tmp/nagios/check_mail_logs_last_run

install -g nagios -o nagios -m 750 -d "$(dirname $LAST_RUN_FILE)"

# :COMMENT:maethor:20210121: Temporaire
if [ -f "${LAST_RUN_FILE/nagios\//}" ] && [ ! -f "$LAST_RUN_FILE" ]; then
    mv ${LAST_RUN_FILE/nagios\//} "$LAST_RUN_FILE"
fi

if [ -f "$LAST_RUN_FILE" ] && [ ! -O "$LAST_RUN_FILE" ]; then
    echo "UNKNOWN: $LAST_RUN_FILE is not owned by $USER"
    exit $RET_UNKNOWN
fi

show_help() {
    echo "$0 [-l LOG_FILE]"
    echo "  -l LOG_FILE : defaults to /var/log/mail.log"
}

function compute() {
    echo "$1" | bc -l | awk '{printf "%.1f", $0}'
}

# process args
while [ ! -z "$1" ]; do 
    case $1 in
        -l)	shift; LOG_FILE=$1 ;;
        -h)	show_help; exit 1 ;;
    esac
    shift
done

# check logs
if [ -z "$LOG_FILE" ]; then
    echo "File(s) not found : $LOG_FILE"
    exit $E_UNKNOWN
fi

# find last check
if [ ! -f $LAST_RUN_FILE ]; then
    echo "$(date +%H:%M:%S -d '5 min ago')" > $LAST_RUN_FILE
fi

since=$(<$LAST_RUN_FILE)
now=$(date +%H:%M:%S)

echo "$now" > $LAST_RUN_FILE

tmpfile="/tmp/$$.tmp"

/usr/local/bin/dategrep -format rsyslog --start $since $LOG_FILE | grep ' postfix/'  > $tmpfile

tmpfile_in="/tmp/$$_in.tmp"

tmpfile_out="/tmp/$$_out.tmp"

# Outgoing
cat $tmpfile | grep 'postfix/smtp\[' | egrep -v 'relay=[^\s\[]*[127\.0\.0\.1]'> $tmpfile_out

out_bounced=$(cat $tmpfile_out | grep 'status=bounced' -c)
out_deferred=$(cat $tmpfile_out | grep 'status=deferred' -c)
out_sent=$(cat $tmpfile_out | grep 'status=sent' -c)

# Incoming
cat $tmpfile | egrep 'postfix/(pipe|cleanup)\[' > $tmpfile_in

in_accepted=$(cat $tmpfile_in | grep 'status=sent' -c)
in_virus=$(cat $tmpfile_in | grep 'Infected' -c)
in_spam=$(cat $tmpfile_in | grep 'Spam message rejected' -c)
in_ratelimit=$(cat $tmpfile_in | grep 'Rate limit exceeded' -c)
in_greylist=$(cat $tmpfile_in | grep 'Try again later' -c)
in_reject=$(cat $tmpfile | grep postfix/smtpd | grep 'NOQUEUE: reject' -c)

now_s=$(date -d $now +%s)
since_s=$(date -d $since +%s)
period=$(( $now_s - $since_s ))

rate_out_bounced=$(compute "$out_bounced * 60 / $period")
rate_out_deferred=$(compute "$out_deferred * 60 / $period")
rate_out_sent=$(compute "$out_sent * 60 / $period")

rate_in_accepted=$(compute "$in_accepted * 60 / $period")
rate_in_virus=$(compute "$in_virus * 60 / $period")
rate_in_spam=$(compute "$in_spam * 60 / $period")
rate_in_ratelimit=$(compute "$in_ratelimit * 60 / $period")
rate_in_greylist=$(compute "$in_greylist * 60 / $period")
rate_in_reject=$(compute "$in_reject * 60 / $period")

PERFDATA="o_sent=$rate_out_sent; o_bounced=$rate_out_bounced; o_deferred=$rate_out_deferred; i_accepted=$rate_in_accepted; i_virus=$rate_in_virus; i_spam=$rate_in_spam; i_ratelimit=$rate_in_ratelimit; i_greylist=$rate_in_greylist; i_reject=$rate_in_reject;"

RET_MSG="$in_accepted messages received and $out_sent messages sent in the last $period seconds | $PERFDATA"

#RET_MSG="in the last $period seconds : out_sent=$out_sent ($rate_out_sent/min) out_bounced=$out_bounced  ($rate_out_bounced/min) out_deferred=$out_deferred ($rate_out_deferred/min) in_accepted=$in_accepted ($rate_in_accepted/min) in_virus=$in_virus ($rate_in_virus/min) in_spam=$in_spam ($rate_in_spam/min) in_ratelimit=$in_ratelimit ($rate_in_ratelimit/min) in_greylist=$in_greylist ($rate_in_greylist/min) in_reject=$in_reject ($rate_in_reject/min) | $PERFDATA"


RET_MSG="OK - $RET_MSG"
RET_CODE=$E_OK

if cat $tmpfile | egrep -q 'warning: database .* is older than source file'; then
    RET_MSG="WARNING - Old postfix database file - $RET_MSG"
    RET_CODE=$E_WARNING
fi

rm $tmpfile
rm $tmpfile_in
rm $tmpfile_out

echo $RET_MSG
exit $RET_CODE
