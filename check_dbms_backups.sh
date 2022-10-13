#!/bin/bash
#
# This plugins search for running databases and checks that a backup is configured in backupninja
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

declare -A dbms_datadirs=(
    ['mongodb']="/var/lib/mongodb"
    ['pgsql']="/var/lib/postgresql"
    ['mysql']="/var/lib/mysql"
    ['ldap']="/var/lib/slapd"
    ['couchbase']="/opt/couchbase/var/lib/couchbase"
    ['elasticsearch']="/var/lib/elasticsearch"
)

declare -A dbms_backupdirs=(
    ['mongodb']="/var/backups/mongodb"
    ['pgsql']="/var/backups/postgres"
    ['mysql']="/var/backups/mysql"
    ['ldap']="/var/backups/ldap"
    ['couchbase']="/var/backups/couchbase"
    ['elasticsearch']="/var/backups/elasticsearch"
)

ok=""
ignored=""

for dbms in "${!dbms_checks[@]}"; do
    running=false
    datadir=false
    # Does not cost anything to double the check, either process is running or standard datadir exists
    if eval "${dbms_checks[$dbms]}" > /dev/null 2>&1; then
        running=true
    elif [ -n "$(find "${dbms_datadirs[$dbms]}" -mindepth 1 -type d 2>/dev/null)" ]; then
        datadir=true
    fi

    if $running || $datadir; then
        if [ -f "${dbms_backupdirs[$dbms]}/README" ]; then
            ignored="$ignored $dbms"
        else
            if ! grep -qR "^### backupninja $dbms" /etc/backup.d; then
                if $running; then
                    echo "CRITICAL : $dbms is running but missing in /etc/backup.d"
                else
                    echo "CRITICAL : ${dbms_datadirs[$dbms]} exists but $dbms is missing in /etc/backup.d"
                fi
                exit 2
            fi
            if [ "$dbms" == "elasticsearch" ]; then
                if ! out=$(/usr/local/nagios/plugins/check_all_files_age.sh "${dbms_backupdirs[$dbms]}" "-maxdepth 2 -not -name incompatible-snapshots"); then
                    echo "$dbms: $out"
                    exit 2
                fi
            else
                if ! out=$(/usr/local/nagios/plugins/check_all_files_age.sh "${dbms_backupdirs[$dbms]}"); then
                    echo "$dbms: $out"
                    exit 2
                fi
            fi
            ok="$ok $dbms"
        fi
    else
        # Check for old backups that can be removed
        if [ -d "${dbms_datadirs[$dbms]}" ]; then
            if ! /usr/local/nagios/plugins/check_all_files_age.sh "${dbms_backupdirs[$dbms]}" > /dev/null; then
                echo "CRITICAL : Old backup found in ${dbms_datadirs[$dbms]}"
                exit 2
            fi
        fi
    fi
done

# :TODO:maethor:20220922: Display ignored
if [ -z "$ok" ] ; then
    echo "OK : no database to backup on this server."
else
    echo "OK : $ok backups are configured in backupninja."
fi
exit 0
