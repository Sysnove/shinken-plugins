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

services="addok addok-wrapper apache2 atd atop bind9 ceph clamav-daemon couchdb cron dibbler-client docker dovecot elasticsearch exim4 fail2ban influxdb lm-sensors logstash lsyncd mailgraph memcached mongodb mongod nagios-nrpe-server nfs-kernel-server nginx npcd ntp openvpn pdns pgbouncer php5-fpm php7.0-fpm php7.1-fpm php7.2-fpm pm2-www-data pm2-gitlab-runner postfix pure-ftpd-mysql rabbitmq-server redis-server repmgrd resolvconf rspamd rsyslog sentry-worker shorewall shorewall6 slapd ssh uwsgi unbound varnish"

down=""

for service in $services; do
    if [ -f "/etc/init.d/$service" ] || [ -f "/lib/systemd/system/${service}.service" ] || [ -f "/etc/systemd/system/${service}.service" ]; then
        if [ "$service" = "drbd" ] && [ -x /usr/sbin/gnt-cluster ]; then
            # Ignore drbd service on Ganeti nodes.
            continue
        fi
        if [ "$service" = "nfs-kernel-server" ] && [ -f /proc/drbd ] && grep -q Secondary/Primary /proc/drbd; then
            # Ignore nfs-kernel-server when first drbd is secondary
            continue
        fi
        service "$service" status >/dev/null || down="$down $service"
    fi
done

# Multi-instance postfix, check postfix@-
if [ -f /lib/systemd/system/postfix@.service ] && grep -q 'bookworm' /etc/debian_version; then
    service "postfix@-" status >/dev/null || down="$down postfix@-"
fi

# Postgres special case : 4 means that postgresql-common is installed but not
# postgresql-server, so it's OK if postgres is not running
if [ -f /etc/init.d/postgresql ]; then
    service postgresql status >/dev/null
    s=$?
    [ $s -ne 0 ] && [ $s -ne 4 ] && down="$down postgresql"
fi

# Special case, pureftp can be running but failed.
# We could make a dedicaded shinken service for this, but we prefer to avoid.
if [ -f /etc/init.d/pure-ftpd ] || [ -f /etc/init.d/pure-ftpd-mysql ]; then
    if ! /usr/lib/nagios/plugins/check_ftp -H localhost >/dev/null; then
        down="$down pure-ftpd"
    fi
fi

if [ "$down" != "" ]; then
    echo "WARNING - Services down:$down"
    exit $STATE_WARNING
else

    # Nginx special case : check if nginx -t is OK
    if [ -f "/lib/systemd/system/nginx.service" ]; then
        if ! /usr/sbin/nginx -t >/dev/null 2>&1; then
            echo "WARNING - Nginx configuration error, please check nginx -t"
            exit $STATE_WARNING
        fi
    fi

    # Apache2 special case : check if apachectl configtest is OK
    if [ -f "/lib/systemd/system/apache2.service" ]; then
        if ! /usr/sbin/apachectl configtest >/dev/null 2>&1; then
            echo "WARNING - Apache2 configuration error, please check apachectl configtest"
            exit $STATE_WARNING
        fi
    fi

    echo "OK - All services are running."
    exit $STATE_OK
fi
