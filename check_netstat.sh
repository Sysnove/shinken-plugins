#!/bin/bash

# 20190926: Added inspeed_max and outspeed_max in persistence file.
# Will be used in future work to guess right thresholds depending on the interface.
# 20191030: Use inspeed_max and outspeed_max to compute per-interface thresholds

RET_OK=0
RET_WARNING=1
RET_CRITICAL=2
RET_UNKNOWN=3

LAST_RUN_FILE=/var/tmp/nagios/check_netstat_last_run
RUN_FILE=$LAST_RUN_FILE.new

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
    exit $RET_UNKNOWN
fi


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


DEFAULTMAXBPS=$((MAX*1000000))

# find last check
if [ ! -f $LAST_RUN_FILE ]; then
    date +s -d '5 min ago' > $LAST_RUN_FILE
fi

since=$(head -n 1 "$LAST_RUN_FILE")
now=$(date +%s)
echo "$now" > $RUN_FILE

IFS=$'\n'

notrunning=0

RET=$RET_OK

function convert_readable {
    if [ "$1" -gt 1000000000 ] ; then
        echo $(($1 / 1000000000))G
    elif [ "$1" -gt 1000000 ] ; then
        echo $(($1 / 1000000))M
    elif [ "$1" -gt 1000 ] ; then
        echo $(($1 / 1000))k
    else
        echo "$1"
    fi
}

for line in $(tail -n+3 /proc/net/dev | grep -v "no statistics"); do
    name=$(echo "$line" | awk '{print $1}' | cut -d ':' -f 1)

    if [[ ! $name =~ ^(eth|en|tun|br) ]] ; then
        continue
    fi

    if [[ $name =~ ^br-[0-9a-f]{12} ]]; then # Docker bridge changes name frequently
        continue
    fi

    rbytes=$(echo "$line" | awk '{print $2}')
    tbytes=$(echo "$line" | awk '{print $10}')

    if ! /sbin/ifconfig "$name" | grep -q RUNNING; then
        notrunning=$((notrunning + 1))
        continue
    fi

    lastrbytes=$(grep "$name|" $LAST_RUN_FILE | cut -d '|' -f 2)
    lasttbytes=$(grep "$name|" $LAST_RUN_FILE | cut -d '|' -f 3)
    inspeed_max=$(grep "$name|" $LAST_RUN_FILE | cut -d '|' -f 4)
    outspeed_max=$(grep "$name|" $LAST_RUN_FILE | cut -d '|' -f 5)

    [ -z "$lastrbytes" ] && lastrbytes=$rbytes
    [ -z "$lasttbytes" ] && lasttbytes=$tbytes
    [ -z "$inspeed_max" ] && inspeed_max=0
    [ -z "$outspeed_max" ] && outspeed_max=0

    interval=$((now - since))

    inspeed=$(((rbytes - lastrbytes) * 8 / interval))
    outspeed=$(((tbytes - lasttbytes) * 8 / interval))

    if [ $interval -gt 120 ]; then # avoid to register bursts
        [ $inspeed -gt $inspeed_max ] && inspeed_max=$inspeed
        [ $outspeed -gt $outspeed_max ] && outspeed_max=$outspeed
    fi

    echo "$name|$rbytes|$tbytes|$inspeed_max|$outspeed_max" >> $RUN_FILE

    # We don't want thresholds too low
    [ $inspeed_max -lt $DEFAULTMAXBPS ] && inspeed_max=$DEFAULTMAXBPS
    [ $outspeed_max -lt $DEFAULTMAXBPS ] && outspeed_max=$DEFAULTMAXBPS

    inspeed_warn=$(((WARN*inspeed_max)/100))
    inspeed_crit=$(((CRIT*inspeed_max)/100))
    outspeed_warn=$(((WARN*outspeed_max)/100))
    outspeed_crit=$(((CRIT*outspeed_max)/100))

    if [[ ! $name =~ ^br ]] ; then
        if [ $inspeed -gt $inspeed_crit ] || [ $outspeed -gt $outspeed_crit ] ; then
            RET=$RET_CRITICAL
        elif [ $inspeed -gt $inspeed_warn ] || [ $outspeed -gt $outspeed_warn ] ; then
            if [ $RET -lt $RET_CRITICAL ] ; then
                RET=$RET_WARNING
            fi
        fi
    fi

    data="$data$name:UP (in=$(convert_readable $inspeed)bps/out=$(convert_readable $outspeed)bps), "
    perfdata="$perfdata '${name}_in_bps'=${inspeed}bps;$inspeed_warn;$inspeed_crit;0 '${name}_out_bps'=${outspeed}bps;$outspeed_warn;$outspeed_crit;0"
done

data="${data::-2}"

mv $RUN_FILE $LAST_RUN_FILE

if [ $notrunning -gt 0 ]; then
    echo "${data} and $notrunning not running | $perfdata"
else
    echo "${data} | $perfdata"
fi

exit $RET
