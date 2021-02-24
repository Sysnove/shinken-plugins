#!/bin/sh

databases=""

if pgrep -f /usr/bin/mongod > /dev/null; then
    if [ ! -f /etc/backup.d/30.mongodb ]; then
        if ! grep -q mongodb /etc/backup.d/.backupninja_ignores; then
            echo "CRITICAL : Missing mongodb backup"
            exit 2
        fi
    else
        databases="$databases mongodb"
    fi
fi

if pgrep postgres -u postgres > /dev/null; then
    if [ ! -f /etc/backup.d/20.pgsql ]; then
        if ! grep -q postgres /etc/backup.d/.backupninja_ignores; then
            echo "CRITICAL : Missing postgresql backup"
            exit 2
        fi
    else
        databases="$databases postgres"
    fi
fi

if pgrep mysql -u mysql > /dev/null; then
    if [ ! -f /etc/backup.d/20.mysql ]; then
        if ! grep -q mysql /etc/backup.d/.backupninja_ignores; then
            echo "CRITICAL : Missing mysql backup"
            exit 2
        fi
    else
        databases="$databases mysql"
    fi
fi

if pgrep slapd > /dev/null; then
    if [ ! -f /etc/backup.d/30.ldap ]; then
        if ! grep -q ldap /etc/backup.d/.backupninja_ignores; then
            echo "CRITICAL : Missing ldap backup"
            exit 2
        fi
    else
        databases="$databases slapd"
    fi
fi

if pgrep beam -u couchbase > /dev/null; then
    if [ ! -f /etc/backup.d/41.sh ]; then
        if ! grep -q couchbase /etc/backup.d/.backupninja_ignores; then
            echo "CRITICAL : Missing couchbase backup"
            exit 2
        fi
    else
        databases="$databases couchbase"
    fi
fi

if pgrep java -u elasticsearch > /dev/null; then
    if [ ! -f /etc/backup.d/40.sh ]; then
        if ! grep -q elasticsearch /etc/backup.d/.backupninja_ignores; then
            echo "CRITICAL : Missing elasticsearch backup"
            exit 2
        fi
    else
        databases="$databases elasticsearch"
    fi
fi

# :TODO:maethor:190109: Couchbase, couchdb… ?

if [ -z "$databases" ] ; then
    echo "OK : no database to backup on this server."
else
    echo "OK : $databases backups are configured in backupninja."
fi
exit 0
