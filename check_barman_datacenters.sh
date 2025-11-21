#!/bin/bash

barman_dc="$(cat /etc/sysnove.json | jq -r '.host.location')"
if [ "$(echo "$barman_dc" | wc -w)" -lt 2 ]; then
    echo "UNKNOWN - $(hostname) location is not properly described in /etc/sysnove.json"
    exit 3
fi

ret_code=0

for s in $(sudo -u barman barman list-servers --minimal); do
    dc=$(sudo -u barman ssh "postgres@$s" cat /etc/sysnove.json | jq -r '.host.location' | sed 's/Dedibox/Online/g')
    if [ -z "$dc" ]; then
        echo "UNKNOWN - Could not retrieve datacenter for $s"
        ret_code=3
    elif [ "$(echo "$barman_dc" | wc -w)" -lt 2 ]; then
        echo "UNKNOWN - $s location is not properly described in /etc/sysnove.json"
        ret_code=3
    elif [ "$dc" == "$barman_dc" ]; then
        echo "WARNING - $s and $(hostname) are both in $dc"
        ret_code=1
    fi
done

if [ $ret_code -eq 0 ]; then
    echo "OK - All backuped servers are in a different DC than $(hostname)"
fi

exit $ret_code
