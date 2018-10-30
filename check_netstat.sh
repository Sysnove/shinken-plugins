#!/bin/bash

OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

LAST_RUN_FILE=/var/tmp/check_netstat_last_run
RUN_FILE=$LAST_RUN_FILE.new

WARN=800000000
CRIT=900000000
MAX=1000000000

# find last check
if [ ! -f $LAST_RUN_FILE ]; then
    echo "$(date +s -d '5 min ago')" > $LAST_RUN_FILE
fi

since=$(cat $LAST_RUN_FILE | head -n 1)
now=$(date +%s)
echo "$now" > $RUN_FILE

IFS=$'\n'

notrunning=0

RET=$OK

function convert_readable {
    if [ $1 -gt 1000000000 ] ; then
        echo $(($1 / 1000000000))G
    elif [ $1 -gt 1000000 ] ; then
        echo $(($1 / 1000000))M
    elif [ $1 -gt 1000 ] ; then
        echo $(($1 / 1000))k
    else
        echo $1
    fi
}

for line in $(cat /proc/net/dev | tail -n+3 | grep -v "no statistics"); do
    name=$(echo $line | awk '{print $1}' | cut -d ':' -f 1)

    if [[ ! $name =~ ^(eth|en|tun|br) ]] ; then
        continue
    fi

    rbytes=$(echo $line | awk '{print $2}')
    tbytes=$(echo $line | awk '{print $10}')

    if ! /sbin/ifconfig $name | grep -q RUNNING; then
        notrunning=$(($notrunning + 1))
        continue
    fi

    echo "$name|$rbytes|$tbytes" >> $RUN_FILE

    lastrbytes=$(grep $name $LAST_RUN_FILE | cut -d '|' -f 2)
    lasttbytes=$(grep $name $LAST_RUN_FILE | cut -d '|' -f 3)

    [ -z "$lastrbytes" ] && lastrbytes=$rbytes
    [ -z "$lasttbytes" ] && lasttbytes=$tbytes

    inspeed=$((($rbytes - $lastrbytes) * 8 / ($now - $since)))
    outspeed=$((($tbytes - $lasttbytes) * 8 / ($now - $since)))

    if [ $inspeed -gt $CRIT -a $outspeed -gt $CRIT ] ; then
        RET=$WARN
    elif [ $inspeed -gt $WARN -a $outspeed -gt $CRIT -a $RET -lt $CRIT ] ; then
        RET=$CRIT
    fi

    data="$data$name:UP (in=$(convert_readable $inspeed)bps/out=$(convert_readable $outspeed)bps), "
    perfdata="$perfdata '${name}_in_bps'=${inspeed}bps;$WARN;$CRIT;0;$MAX '${name}_out_bps'=${outspeed}bps;$WARN;$CRIT;0;$MAX"
done

data="${data::-2}"

mv $RUN_FILE $LAST_RUN_FILE

if [ $notrunning -gt 0 ]; then
    echo "${data} and $notrunning not running | $perfdata"
else
    echo "${data} | $perfdata"
fi

exit $RET
