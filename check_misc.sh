#!/bin/sh

hostnamectl=$(hostnamectl status)
server_type='baremetal'

if echo "$hostnamectl" | grep 'Chassis: vm'; then
    server_type='vm'
elif echo "$hostnamectl" | grep 'Chassis: container'; then
    server_type='container'
fi

set -e

/usr/lib/nagios/plugins/check_ntp_time -H 0.debian.pool.ntp.org
/usr/bin/sudo /usr/local/nagios/plugins/check_inotify_user_instances.sh

if [ "$server_type" = "baremetal" ]; then
    /usr/lib/nagios/plugins/check_sensors
fi
