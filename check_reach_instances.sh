#!/bin/sh

#
# Guillaume Subiron, Sysnove, 2014
#
# Description :
#
# This plugin checks if all installed daemons are running.
# Works on Debian.
#
# Copyright 2014 Guillaume Subiron <guillaume@sysnove.fr>
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more details.
# 

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

instances=$(sudo ssh gnt.sysnove.net gnt-instance list --no-headers | grep running | cut -d ' ' -f 1)
errors=""

for instance in $instances ; do
    /usr/lib/nagios/plugins/check_nrpe -4 -H $instance -t 1 -u -c check_nrpe > /dev/null || errors="$errors $instance"
done

if [ "$errors" != "" ] ; then
    echo "ERROR - Instances unreachable:$errors"
    exit $STATE_CRITICAL
else
    echo "OK - All instances are reachable."
    exit $STATE_OK
fi
