#!/bin/bash

barman_dc="$(cat /etc/sysnove.json | jq -r '.host.location')"
if [ $(echo "$barman_dc" | wc -w) -lt 2 ]; then
    echo "UNKNOWN - $(hostname) location is not properly described in /etc/sysnove.json"
    exit 3
fi

ret_code=0

for s in $(sudo -u barman barman list-servers --minimal); do
    dc=$(sudo -u barman ssh postgres@$s cat /etc/sysnove.json | jq -r '.host.location' | sed 's/Dedibox/Online/g')

    if [ -z "$dc" ]; then
        echo "UNKNOWN - Could not retrieve datacenter for $s"
        ret_code=3
    elif [ "$(echo "$dc" | wc -w)" -lt 2 ]; then
        echo "UNKNOWN - $s location is not properly described in /etc/sysnove.json"
        ret_code=3
    elif [ "$dc" == "$barman_dc" ]; then
        repmgr_cluster=$(sudo -u barman ssh "postgres@$s" repmgr cluster show 2>/dev/null | grep -Eo "host=[^ ]*" | cut -d "=" -f 2)
        all_the_same=true
        for repmgr_s in $repmgr_cluster; do
            dc2=$(sudo -u barman ssh "postgres@$s" ssh "postgres@$repmgr_s" cat /etc/sysnove.json | jq -r '.host.location' | sed 's/Dedibox/Online/g')
            if [ -z "$dc2" ]; then
                echo "UNKNOWN - Could not retrieve datacenter for $repmgr_s"
                ret_code=3
            elif [ "$(echo "$dc2" | wc -w)" -lt 2 ]; then
                echo "UNKNOWN - $repmgr_s location is not properly described in /etc/sysnove.json"
                ret_code=3
            elif [ "$dc2" != "$barman_dc" ]; then
                all_the_same=false
            fi
        done
        if $all_the_same; then
            echo "WARNING - $s and $(hostname) are both in $dc"
            ret_code=1
        fi
    fi
done

if [ $ret_code -eq 0 ]; then
    echo "OK - All backuped servers are in a different DC than $(hostname)"
fi

exit $ret_code
