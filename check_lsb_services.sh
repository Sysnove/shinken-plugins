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

services="addok addok-wrapper apache2 atd bind9 ceph clamav-daemon couchdb cron dibbler-client dovecot exim4 fail2ban fcgiwrap glassfish gitlab lm-sensors mailgraph memcached mongodb nagios-nrpe-server nginx npcd ntp openvpn pgbouncer php5-fpm php7.0-fpm php7.1-fpm postfix pure-ftpd-mysql rabbitmq-server redis-server repmgrd resolvconf rmilter rspamd rsyslog shinken shorewall shorewall6 slapd ssh uwsgi"

down=""

for service in $services ; do
    if [ -f /etc/init.d/$service -o -f /lib/systemd/system/${service}.service ] ; then
        service $service status > /dev/null || down="$down $service"
    fi
done

# Postgres special case : 4 means that postgresql-common is installed but not
# postgresql-server, so it's OK if postgres is not running
if [ -f /etc/init.d/postgresql ] ; then
    service postgresql status > /dev/null
    s=$?
    [ $s -ne 0 -a $s -ne 4 ] && down="$down postgresql"
fi

if [ "$down" != "" ] ; then
    echo "WARNING - Services down:$down"
    exit $STATE_WARNING
else
    echo "OK - All services are running."
    exit $STATE_OK
fi

