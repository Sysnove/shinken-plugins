#!/bin/bash

declare -A dbs=(
    ['mongodb']="pgrep -f /usr/bin/mongod"
    ['postgres']="pgrep postgres -u postgres"
    ['mysql']="pgrep mysql -u mysql"
    ['slapd']="pgrep slapd"
    ['couchbase']="pgrep beam -u couchbase"
    ['elasticsearch']="pgrep java -u elasticsearch"
)

databases=""
ignored=""

for dbms in "${!dbs[@]}"; do
    if eval "${dbs[$dbms]}" > /dev/null 2>&1; then
        if ! grep -q "# ignore $dbms" /etc/backupninja.conf; then
            ignored="$ignored $dbms"
        else
            if grep -qR "^### backupninja $dbms" /etc/backup.d; then
                echo "CRITICAL : Missing $dbms backupninja handler"
                exit 2
            fi
            backupdir=$(grep -R "^### backupninja $dbms" /etc/backup.d | cut -d ' ' -f 4)
            if ! /usr/local/nagios/plugins/check_all_files_age.sh "$backupdir"; then
                exit 2
            fi
            databases="$databases $dbms"
        fi
    fi
done

if [ -z "$databases" ] ; then
    echo "OK : no database to backup on this server."
else
    echo "OK : $databases backups are configured in backupninja."
fi
exit 0
