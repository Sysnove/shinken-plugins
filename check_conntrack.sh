#!/bin/bash

RET_OK=0
RET_WARN=1
RET_UNKNOWN=3

WEB_WARN=5000
ALL_WARN=10000

while getopts "w:a:" option
do
    case $option in
        w)
            WEB_WARN=$OPTARG
            ;;
        a)
            ALL_WARN=$OPTARG
            ;;
        *)
    esac
done

MY_IPS=$(/sbin/ifconfig | sed -En 's/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | paste -sd "|" -)

all=$(/usr/sbin/conntrack -L | awk '{print $5}' | grep -E -c -v "src=($MY_IPS)" 2>/dev/null)

if [[ -z "$all" ]]; then
    /usr/sbin/conntrack -C
    exit $RET_UNKNOWN
fi

http=$(/usr/sbin/conntrack -L -p tcp --dport 80 | awk '{print $5}' | grep -E -c -v "src=($MY_IPS)" 2>/dev/null)
https=$(/usr/sbin/conntrack -L -p tcp --dport 443 | awk '{print $5}' | grep -E -c -v "src=($MY_IPS)" 2>/dev/null)

web=$((http + https))

perfdata="all=${all};$ALL_WARN web=${web};$WEB_WARN"

if [[ $all -gt $ALL_WARN ]]; then
    echo "WARNING - $all external connections | $perfdata"
    exit $RET_WARN
fi

if [[ $web -gt $WEB_WARN ]]; then
    echo "WARNING - $web external web connections | $perfdata"
    exit $RET_WARN
fi

echo "OK - $all external connections, $web external web connections | $perfdata"
exit $RET_OK

