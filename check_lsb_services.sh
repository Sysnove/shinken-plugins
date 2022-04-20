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

services="addok addok-wrapper apache2 atd bind9 ceph clamav-daemon couchdb cron dibbler-client docker dovecot elasticsearch exim4 fail2ban lm-sensors logstash lsyncd mailgraph memcached mongodb mongod nagios-nrpe-server nfs-kernel-server nginx npcd ntp openvpn pdns pgbouncer php5-fpm php7.0-fpm php7.1-fpm php7.2-fpm postfix pure-ftpd-mysql rabbitmq-server redis-server repmgrd resolvconf rspamd rsyslog sentry-worker shorewall shorewall6 slapd ssh uwsgi unbound varnish drbd"

down=""

for service in $services ; do
    if [ -f "/etc/init.d/$service" ] || [ -f "/lib/systemd/system/${service}.service" ] || [ -f "/etc/systemd/system/${service}.service" ]; then
	if [ "$service" = "drbd" ] && [ -x /usr/sbin/gnt-cluster ]; then
	    # Ignore drbd service on Ganeti nodes.
	    continue
	fi

        service "$service" status > /dev/null || down="$down $service"
    fi
done

# Postgres special case : 4 means that postgresql-common is installed but not
# postgresql-server, so it's OK if postgres is not running
if [ -f /etc/init.d/postgresql ] ; then
    service postgresql status > /dev/null
    s=$?
    [ $s -ne 0 ] && [ $s -ne 4 ] && down="$down postgresql"
fi

if [ "$down" != "" ] ; then
    echo "WARNING - Services down:$down"
    exit $STATE_WARNING
else
    echo "OK - All services are running."
    exit $STATE_OK
fi

