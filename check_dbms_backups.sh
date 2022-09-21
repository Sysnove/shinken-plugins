#!/bin/sh

databases=""
ignored=""

check_dbms_backup () {
    dbms=$1

    if ! grep -q "# ignore $dbms" /etc/backupninja.conf; then
        ignored="$ignored $dbms"
    else
        if ! grep -qR "^### backupninja $dbms" /etc/backup.d; then
            echo "CRITICAL : Missing $dbms backupninja handler"
            exit 2
        fi
        backupdir=$(grep -R "^### backupninja $dbms" /etc/backup.d | cut -d ' ' -f 4)
        if ! /usr/local/nagios/plugins/check_all_files_age.sh "$backupdir"; then
            exit 2
        fi
        databases="$databases $dbms"
    fi
}

if pgrep -f /usr/bin/mongod > /dev/null 2>&1; then
    check_dbms_backup mongodb
fi

if pgrep postgres -u postgres > /dev/null 2>&1; then
    check_dbms_backup postgres
fi

if pgrep mysql -u mysql > /dev/null 2>&1; then
    check_dbms_backup mysql
fi

if pgrep slapd > /dev/null 2>&1; then
    check_dbms_backup slapd
fi

if pgrep beam -u couchbase > /dev/null 2>&1; then
    check_dbms_backup couchbase
fi

if pgrep java -u elasticsearch > /dev/null 2>&1; then
    check_dbms_backup elasticsearch
fi

# :TODO:maethor:190109: Couchbase, couchdb… ?

if [ -z "$databases" ] ; then
    echo "OK : no database to backup on this server."
else
    echo "OK : $databases backups are configured in backupninja."
fi
exit 0
