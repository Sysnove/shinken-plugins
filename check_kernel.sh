#!/bin/sh

# 
# Guillaume Subiron, Sysnove, 2013
#
# Description :
#
# This plugin checks if we're running the newest installed kernel.
# Works on Debian.
#
# Copyright 2013 Guillaume Subiron <guillaume@sysnove.fr>
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more details.
#

# Nagios return codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

currentkernel=$(uname -r)
latestkernel=$(ls -t /boot/vmlinuz-* | sed "s/\/boot\/vmlinuz-//g" | head -n1)
#latestkernel=$(dpkg --get-selections | grep linux-image | grep install | cut -f1 | cut -d\- -f3- | sort | head -n 1)
#latestkernel=$(dpkg-query -W --showformat='${Version}\t${Package}\n' 'linux-image*' | sort | cut -f2 | cut -d\- -f3- | head -n1)

if [ $latestkernel = $currentkernel ] ; then
    echo "OK - Running kernel: $currentkernel;"
    exit $STATE_OK
else
    if [ "$1" = "--warn-only" ] ; then
        echo "KERNEL WARNING - Running kernel: $currentkernel but newer kernel available: $latestkernel."
        exit $STATE_WARNING
    else
        echo "KERNEL CRITICAL - Running kernel: $currentkernel but newer kernel available: $latestkernel."
        exit $STATE_CRITICAL
    fi
fi
