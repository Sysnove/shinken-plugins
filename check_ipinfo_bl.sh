#!/bin/bash

if ! which ipset > /dev/null 2>&1; then
    echo "ipset is not installed"
    exit 0
fi

entries=$(ipset list IPINFO_BL4 | grep 'Number of entries:' | awk '{print $NF}')

if [ -z "$entries" ] ; then
    echo "CRITICAL - no entry in ipset IPINFO_BL4"
    exit 2
elif [ "$entries" -lt 100 ] ; then
    echo "WARNING - $entries entries in ipset IPINFO_BL4"
    exit 1
else
    (
    set -e
    /usr/lib/nagios/plugins/check_file_age -w $((60*60*24*7)) -c $((60*60*24*14)) -W 100000 /var/cache/ipinfo_blacklist.json | cut -d '|' -f 1
    echo "OK - $entries entries in ipset IPINFO_BL4"
    ) | tac
    exit 0
fi
