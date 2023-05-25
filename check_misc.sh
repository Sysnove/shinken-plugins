#!/bin/sh

hostnamectl=$(hostnamectl status)
server_type='baremetal'

if echo "$hostnamectl" | grep -q 'Chassis: vm'; then
    server_type='vm'
elif echo "$hostnamectl" | grep -q 'Chassis: container'; then
    server_type='container'
fi

if [ -d /usr/lib/nagios/plugins ]; then
    NAGIOS_PLUGINS=/usr/lib/nagios/plugins
else
    NAGIOS_PLUGINS=/usr/lib64/nagios/plugins
fi

set -e

$NAGIOS_PLUGINS/check_ntp_time -H 0.debian.pool.ntp.org | cut -d '|' -f 1
/usr/bin/sudo /usr/local/nagios/plugins/check_inotify_user_instances.sh | cut -d '|' -f 1

if [ "$server_type" = "baremetal" ]; then
    $NAGIOS_PLUGINS/check_sensors
fi

echo "OK - Everything is Awesome"
