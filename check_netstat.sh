#!/bin/bash

# 20190926: Added maxinspeed and maxoutspeed in persistence file.
# Will be used in future work to guess right thresholds depending on the interface.

RET_OK=0
RET_WARNING=1
RET_CRITICAL=2
RET_UNKNOWN=3

LAST_RUN_FILE=/var/tmp/check_netstat_last_run
RUN_FILE=$LAST_RUN_FILE.new

WARN=80
CRIT=95
MAX=100

function printHelp {
    echo -e \\n"Help for $0"\\n
    echo -e "Basic usage: $0 -m {maximum} -w {warning} -c {critical}"\\n
    echo "Command switches are optional."
    echo "maximum is at least 100Mbps, but can be computed using the persistence file."
    echo "-w - Sets warning value for bandwidth. Default is 80% of maximum bandwidth"
    echo "-c - Sets critical value for bandwidth. Default is 95% of maximum bandwidth"
    echo "-m - Sets maximum bandwidth, in Mbps. Default is 100 or maximum registered bandwith"
    echo "-h - Displays this help message"
    echo "Example: $0 -m 300 -w 80 -c 90"
    exit 1
}

re='^[0-9]+$'

while getopts :w:c:m:h FLAG; do
    case $FLAG in
        w)
            if ! [[ $OPTARG =~ $re ]] ; then
                echo "error: Not a number" >&2; exit 1
            else
                WARN=$OPTARG
            fi
            ;;
        c)
            if ! [[ $OPTARG =~ $re ]] ; then
                echo "error: Not a number" >&2; exit 1
            else
                CRIT=$OPTARG
            fi
            ;;
        m)
            echo $OPTARG
            if ! [[ $OPTARG =~ $re ]] ; then
                echo "error: Not a number" >&2; exit 1
            else
                MAX=$OPTARG
            fi
            ;;
        h)
            printHelp
            ;;
        \?)
            echo -e \\n"Option - $OPTARG not allowed."
            printHelp
            exit $RET_CRITICAL
            ;;
    esac
done

shift $((OPTIND-1))


MAXBPS=$((MAX*1000000))
WARNBPS=$(((WARN*MAXBPS)/100))
CRITBPS=$(((CRIT*MAXBPS)/100))


# find last check
if [ ! -f $LAST_RUN_FILE ]; then
    echo "$(date +s -d '5 min ago')" > $LAST_RUN_FILE
fi

since=$(cat $LAST_RUN_FILE | head -n 1)
now=$(date +%s)
echo "$now" > $RUN_FILE

IFS=$'\n'

notrunning=0

RET=$RET_OK

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

    lastrbytes=$(grep $name $LAST_RUN_FILE | cut -d '|' -f 2)
    lasttbytes=$(grep $name $LAST_RUN_FILE | cut -d '|' -f 3)
    maxinspeed=$(grep $name $LAST_RUN_FILE | cut -d '|' -f 4)
    maxoutspeed=$(grep $name $LAST_RUN_FILE | cut -d '|' -f 5)

    [ -z "$lastrbytes" ] && lastrbytes=$rbytes
    [ -z "$lasttbytes" ] && lasttbytes=$tbytes
    [ -z "$maxinspeed" ] && maxinspeed=0
    [ -z "$maxoutspeed" ] && maxoutspeed=0

    # If max registered speed is greater than MAXBPS,
    # then update MAXBPS to use max registered speed
    [ $maxinspeed -gt $MAXBPS ] && MAXBPS=$maxinspeed
    [ $maxoutspeed -gt $MAXBPS ] && MAXBPS=$maxoutspeed

    inspeed=$((($rbytes - $lastrbytes) * 8 / ($now - $since)))
    outspeed=$((($tbytes - $lasttbytes) * 8 / ($now - $since)))

    [ $inspeed -gt $maxinspeed ] && maxinspeed=$inspeed
    [ $outspeed -gt $maxoutspeed ] && maxoutspeed=$outspeed

    echo "$name|$rbytes|$tbytes|$maxinspeed|$maxoutspeed" >> $RUN_FILE

    if [[ ! $name =~ ^br ]] ; then
        if [ $inspeed -gt $CRITBPS -o $outspeed -gt $CRITBPS ] ; then
            RET=$RET_CRITICAL
        elif [ $inspeed -gt $WARNBPS -o $outspeed -gt $WARNBPS ] ; then
            if [ $RET -lt $RET_CRITICAL ] ; then
                RET=$RET_WARNING
            fi
        fi
    fi

    data="$data$name:UP (in=$(convert_readable $inspeed)bps/out=$(convert_readable $outspeed)bps), "
    perfdata="$perfdata '${name}_in_bps'=${inspeed}bps;$WARNBPS;$CRITBPS;0 '${name}_out_bps'=${outspeed}bps;$WARNBPS;$CRITBPS;0"
done

data="${data::-2}"

mv $RUN_FILE $LAST_RUN_FILE

if [ $notrunning -gt 0 ]; then
    echo "${data} and $notrunning not running | $perfdata"
else
    echo "${data} | $perfdata"
fi

exit $RET
