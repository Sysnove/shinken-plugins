#!/bin/sh

databases=""

if pgrep mongo > /dev/null; then
    databases="$databases mongodb"
    if [ ! -e /etc/backup.d/30.mongodb ]; then
        echo "CRITICAL : Missing mongodb backup"
        exit 2
    fi
fi

if pgrep postgres -u postgres > /dev/null; then
    databases="$databases postgres"
    if [ ! -e /etc/backup.d/20.pgsql ] and ! grep -q postgres /etc/backup.d/.backupninja_ignores; then
        echo "CRITICAL : Missing postgresql backup"
        exit 2
    fi
fi

if pgrep mysql -u mysql > /dev/null; then
    databases="$databases mysql"
    if [ ! -e /etc/backup.d/20.mysql ] and ! grep -q mysql /etc/backup.d/.backupninja_ignores; then
        echo "CRITICAL : Missing mysql backup"
        exit 2
    fi
fi

if pgrep slapd > /dev/null; then
    databases="$databases slapd"
    if [ ! -e /etc/backup.d/30.ldap ]; then
        echo "CRITICAL : Missing ldap backup"
        exit 2
    fi
fi

# :TODO:maethor:190109: Couchbase, couchdb… ?

if [ -z $databases ] ; then
    echo "OK : no database running on this server."
else
    echo "OK : $databases backups are configured in backupninja."
fi
exit 0
