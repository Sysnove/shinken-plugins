#!/bin/sh

databases=""

if pgrep -f /usr/bin/mongod > /dev/null; then
    databases="$databases mongodb"
    if [ ! -e /etc/backup.d/30.mongodb ]; then
        echo "CRITICAL : Missing mongodb backup"
        exit 2
    fi
fi

if pgrep postgres -u postgres > /dev/null; then
    databases="$databases postgres"
    if [ ! -e /etc/backup.d/20.pgsql ]; then
        if ! grep -q postgres /etc/backup.d/.backupninja_ignores; then
            echo "CRITICAL : Missing postgresql backup"
            exit 2
        fi
    fi
fi

if pgrep mysql -u mysql > /dev/null; then
    databases="$databases mysql"
    if [ ! -e /etc/backup.d/20.mysql ]; then
        if ! grep -q mysql /etc/backup.d/.backupninja_ignores; then
            echo "CRITICAL : Missing mysql backup"
            exit 2
        fi
    fi
fi

if pgrep slapd > /dev/null; then
    databases="$databases slapd"
    if [ ! -e /etc/backup.d/30.ldap ]; then
        if ! grep -q ldap /etc/backup.d/.backupninja_ignores; then
            echo "CRITICAL : Missing ldap backup"
            exit 2
        fi
    fi
fi

if pgrep beam -u couchbase > /dev/null; then
    databases="$databases couchbase"
    if [ ! -e /etc/backup.d/41.sh ]; then
        if ! grep -q couchbase /etc/backup.d/.backupninja_ignores; then
            echo "CRITICAL : Missing couchbase backup"
            exit 2
        fi
    fi
fi

# :TODO:maethor:190109: Couchbase, couchdb… ?

if [ -z "$databases" ] ; then
    echo "OK : no database running on this server."
else
    echo "OK : $databases backups are configured in backupninja."
fi
exit 0
