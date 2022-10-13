#!/bin/bash

###
### This plugins checks if there is an up to date backup for various database management systems.
### On replicated clusters, it will check every server and count the number of backups.
### By default we want one backup. Not less, but not much.
###
### Usage: check_dbms_backup.sh [--min 1] [--max 1] (postgresql|mysql|couchbase|mongodb|…)
###


usage() {
    sed -rn 's/^### ?//;T;p' "$0"
}

MIN_BACKUPS=1
MAX_BACKUPS=1
CHECK_USER="root"

while [ $# -gt 1 ]; do
    case "$1" in
        --min) shift
            MIN_BACKUPS="$1"
            ;;
        --max) shift
            MAX_BACKUPS="$1"
            ;;
        -h|--help) usage
            exit 0
            ;;
        *) echo "UNKNOWN argument : $1"
            usage
            exit 3
            ;;
    esac
    shift
done


case $1 in
    postgresql)
        CHECK_COMMAND="/usr/local/nagios/plugins/check_all_files_age.sh /var/backups/postgres"
        CHECK_USER="postgres"
        CLUSTER_HOSTS=$(sudo -u postgres repmgr cluster show 2>&1 | grep -o 'host=[^ ]*' | cut -d '=' -f 2)
        ;;
    mysql)
        CHECK_COMMAND="/usr/local/nagios/plugins/check_all_files_age.sh /var/backups/mysql/sqldump"
        CLUSTER_HOSTS=$(sudo mysql --skip-column-names -sr -e "show slave hosts;" | awk '{print $2}')
        if [ -n "$CLUSTER_HOSTS" ]; then
            CLUSTER_HOSTS="$CLUSTER_HOSTS 127.0.0.1"
        fi
        ;;
    couchbase)
        # TODO couchbase-cli in PATH
        #/opt/couchbase/bin/couchbase-cli server-list -c localhost -u Administrator -p adminpass
        cb_user=$(grep -Eo '\-u ".*" \-p ".*"' /etc/backup.d/21_couchbase.sh 2>/dev/null | cut -d '"' -f 2)
        cb_pass=$(grep -Eo '\-u ".*" \-p ".*"' /etc/backup.d/21_couchbase.sh 2>/dev/null | cut -d '"' -f 4)
        if [ -z "$cb_user" ] || [ -z "$cb_pass" ]; then
            echo "UNKNOWN : Could not find couchbase admin and password"
        fi
        CHECK_COMMAND="/usr/local/nagios/plugins/check_younger_file_age.sh -w 24 -c 76 -d /var/backups/couchbase/"
        CLUSTER_HOSTS=$(/opt/couchbase/bin/couchbase-cli server-list -c localhost -u "$cb_user" -p "$cb_pass" | cut -d ' ' -f 2 | cut -d ':' -f 1)
        ;;
    mongodb)
        CHECK_COMMAND="/usr/local/nagios/plugins/check_younger_file_age.sh -w 24 -c 76 -d /var/backups/mongodb/"
        CLUSTER_HOSTS=$(sudo mongo --quiet --eval "JSON.stringify(rs.status())" | jq -r '.members[] | .name' | cut -d ':' -f 1)
        ;;
    ldap)
        CHECK_COMMAND='/usr/local/nagios/plugins/check_all_files_age.sh /var/backups/ldap'
        CLUSTER_HOSTS=''
        ;;
    elasticsearch)
        elastic_user="$(grep '\-\-user' /etc/backup.d/21_elasticsearch.sh 2>/dev/null | cut -d ':' -f 1 | cut -d '"' -f 2)"
        elastic_pass="$(grep '\-\-user' /etc/backup.d/21_elasticsearch.sh 2>/dev/null | cut -d ':' -f 2 | cut -d '"' -f 1)"
        if [ -n "$elastic_user" ]; then
            CHECK_COMMAND="/usr/local/nagios/plugins/check_elasticsearch_backup.sh $elastic_user $elastic_pass"
        else
            CHECK_COMMAND="/usr/local/nagios/plugins/check_elasticsearch_backup.sh"
        fi
        CLUSTER_HOSTS=''
        ;;
    #lsync)
        #CHECK_COMMAND="grep 'backup_excludes: /srv/***$' /etc/backup.d/91.borg"
        #HOSTS=""
        #;;
    *)
        echo "$1 is not managed"
        exit 3
        ;;
esac

if [ -z "$CLUSTER_HOSTS" ]; then
    output=$($CHECK_COMMAND)
    ret=$?
    if [ $ret -ne 0 ] && [ "$MIN_BACKUPS" -eq 0 ]; then
        echo "OK : $output but MIN_BACKUPS is 0 so it is OK anyway."
        exit 0
    else
        echo "$output"
        exit $ret
    fi
fi

oks=()
noks=()
for host in $CLUSTER_HOSTS; do
    if [ "$host" != "127.0.0.1" ]; then
        output=$(sudo -u $CHECK_USER ssh -oStrictHostKeyChecking=no "$host" "$CHECK_COMMAND" 2>&1)
    else
        output=$($CHECK_COMMAND 2>&1)
    fi
    ret=$?
    if [ $ret -eq 0 ]; then
        last_ok_output=$output
        oks+=("$host")
    else
        if [ $ret -eq 255 ]; then
            echo "UNKNOWN : Could not SSH to $output"
            exit 3
        fi
        noks+=("$host")
    fi
done

nb_oks=${#oks[@]}

if [ "$nb_oks" -lt "$MIN_BACKUPS" ]; then
    echo "CRITICAL : Found $nb_oks OK backups on $CLUSTER_HOSTS. We need at least $MIN_BACKUPS."
    exit 2
elif [ "$nb_oks" -gt "$MAX_BACKUPS" ]; then
    echo "WARNING : Found backups on more than $MAX_BACKUPS host -" "${oks[@]}"
    exit 1
else
    echo "$last_ok_output on" "${oks[@]}"
    exit 0
fi
