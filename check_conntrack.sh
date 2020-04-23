#!/bin/bash

RET_OK=0
RET_WARN=1
RET_CRIT=2
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
    esac
done

all=$(/usr/sbin/conntrack -C 2>/dev/null)

if [[ -z "$all" ]]; then
    /usr/sbin/conntrack -C
    exit $RET_UNKNOWN
fi

http=$(/usr/sbin/conntrack -L -p tcp --dport 443 2>/dev/null | wc -l)
https=$(/usr/sbin/conntrack -L -p tcp --dport 443 2>/dev/null | wc -l)

web=$(($http+$https))

perfdata="all=${all}c;$ALL_WARN web=${web}c;$WEB_WARN"

if [[ $all -gt $ALL_WARN ]]; then
    echo "WARNING - $all connections | $perfdata"
    exit $RET_WARN
fi

if [[ $web -gt $WEB_WARN ]]; then
    echo "WARNING - $web web connections | $perfdata"
    exit $RET_WARN
fi

echo "OK - $all connections, $web web connections | $perfdata"
exit $RET_OK

