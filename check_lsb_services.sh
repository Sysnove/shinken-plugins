#!/bin/sh

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

services="amavis apache2 atd bind9 cron dibbler-client dovecot exim4 fail2ban fcgiwrap glassfish gitlab lm-sensors mailgraph mdadm memcached mongodb nagios-nrpe-server nginx npcd ntp openvpn pgbouncer php5-fpm postfix postgresql pure-ftpd-mysql rabbitmq-server redis-server resolvconf rsyslog shinken shorewall shorewall6 slapd spamassassin ssh uwsgi"

down=""

for service in $services ; do
    if [ -f /etc/init.d/$service ] ; then
        /usr/sbin/service $service status > /dev/null || down="$down $service"
    fi
done

if [ "$down" != "" ] ; then
    echo "WARNING - Services down:$down"
    exit $STATE_WARNING
else
    echo "OK - All services are running."
    exit $STATE_OK
fi

