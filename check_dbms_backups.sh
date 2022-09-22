#!/bin/bash
#
# This plugins search for running databases and check that a backup is configured in backupninja
# for each database management system.
# WARNING : This plugin does not replace check_mysql_backup, check_elasticsearch_backup, etc.

declare -A dbms_checks=(
    ['mongodb']="pgrep -f /usr/bin/mongod"
    ['pgsql']="pgrep postgres -u postgres"
    ['mysql']="pgrep mysql -u mysql || pgrep mariadb -u mysql"
    ['ldap']="pgrep slapd"
    ['couchbase']="pgrep beam -u couchbase"
    ['elasticsearch']="pgrep java -u elasticsearch"
)

ok=""
ignored=""

for dbms in "${!dbms_checks[@]}"; do
    if eval "${dbms_checks[$dbms]}" > /dev/null 2>&1; then
        if grep -q "# ignore $dbms" /etc/backupninja.conf; then
            ignored="$ignored $dbms"
        else
            if ! grep -qR "^### backupninja $dbms" /etc/backup.d; then
                echo "CRITICAL : Missing /etc/backup.d config for $dbms"
                exit 2
            fi
            backupdir=$(grep "^### backupninja $dbms" "/etc/backup.d/21_$dbms"* | cut -d ' ' -f 4)
            if [ "$dbms" == "elasticsearch" ]; then
                if ! out=$(/usr/local/nagios/plugins/check_all_files_age.sh "$backupdir" "-maxdepth 2 -not -name incompatible-snapshots"); then
                    echo "$dbms: $out"
                    exit 2
                fi
            else
                if ! out=$(/usr/local/nagios/plugins/check_all_files_age.sh "$backupdir"); then
                    echo "$dbms: $out"
                    exit 2
                fi
            fi
            ok="$ok $dbms"
        fi
    fi
done

if [ -z "$ok" ] ; then
    echo "OK : no database to backup on this server."
else
    echo "OK : $ok backups are configured in backupninja."
fi
exit 0
