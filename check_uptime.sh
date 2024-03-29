#!/bin/bash

###
### This plugin checks the serveur uptime and kernel version.
### Thresholds are used to invite the user to reboot the server.
###
### CopyLeft 2021 Guillaume Subiron <guillaume@sysnove.fr>
### 
### This work is free. You can redistribute it and/or modify it under the
### terms of the Do What The Fuck You Want To Public License, Version 2,
### as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more details.
###
### Usage:
### - check_uptime.sh
### - check_uptime.sh -w 300
### - check_uptime.sh -w 300 -c 500
### - check_uptime.sh -d bullseye # expected distribution codename
###
### Warning and Critical thresholds are in days.
###

usage() {
    sed -rn 's/^### ?//;T;p' "$0"
}

while getopts "w:c:d:" option; do
    case "${option}" in
        w)
            WARN=${OPTARG}
            ;;
        c)
            CRIT=${OPTARG}
            ;;
        *)
            usage
            exit 3
            ;;
    esac
done

if lsb_release -d | grep -Eq '(Ubuntu|Debian)'; then
    lsb_release_text="$(lsb_release -is) $(lsb_release -rs) $(lsb_release -cs)"
fi


#uptime_in_seconds=$(($(date +%s) - $(date -d "$(uptime -s)" +%s)))
uptime_in_seconds=$(cut -d '.' -f 1 /proc/uptime)

D=$((uptime_in_seconds/60/60/24))
H=$((uptime_in_seconds/60/60%24))
M=$((uptime_in_seconds/60%60))

uptime_text="running for $D days $H hours $M minutes | days=$D;$WARN;$CRIT;0;"
kernel_text=$(uname -sr)
status_text=OK
ret_code=0


currentkernel=$(uname -r)
# shellcheck disable=SC2012
latestkernel=$(ls -t /boot/vmlinuz-* | sed "s/\/boot\/vmlinuz-//g" | head -n1)

if [ "$latestkernel" != "$currentkernel" ] ; then
    kernel_text="$kernel_text ($latestkernel is available)"
    if [ -n "$WARN" ] && [ $D -gt "$WARN" ]; then
        status_text=WARNING
        ret_code=1
    fi

    if [ -n "$CRIT" ] && [ $D -gt "$CRIT" ]; then
        status_text=CRITICAL
        ret_code=2
    fi
fi

echo "$status_text - $lsb_release_text $kernel_text $uptime_text"
exit $ret_code
