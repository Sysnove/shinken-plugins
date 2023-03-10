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
LOCAL_ONLY=false

while [ $# -gt 1 ]; do
    case "$1" in
        --min) shift
            MIN_BACKUPS="$1"
            ;;
        --max) shift
            MAX_BACKUPS="$1"
            ;;
        --local)
            LOCAL_ONLY=true
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
        BACKUP_DIR="/var/backups/postgres"
        if ! $LOCAL_ONLY; then
            CLUSTER_HOSTS=$(sudo -u postgres repmgr cluster show 2>&1 | grep -o 'host=[^ ]*' | cut -d '=' -f 2)
        fi
        ;;
    mysql)
        CHECK_COMMAND="/usr/local/nagios/plugins/check_all_files_age.sh /var/backups/mysql"
        BACKUP_DIR="/var/backups/mysql"
        if ! $LOCAL_ONLY; then
            REPLICAS=$(sudo mysql -e "show slave hosts\G;" | grep 'Host:' | awk '{print $2}')
            MASTER=$(sudo mysql -e "show slave status\G;" | grep -E '(Slave_SQL_Running|Master_Host):' | grep 'Slave_SQL_Running: Yes' -B 1 | grep "Master_Host" | awk '{print $2}')
            if [ -n "$REPLICAS" ] || [ -n "$MASTER" ]; then
                CLUSTER_HOSTS="$REPLICAS $MASTER 127.0.0.1"
            fi
        fi
        ;;
    couchbase)
        if [ -e /etc/backup.d/21_cbbackupmgr.sh ]; then
            cb_user=$(grep '^ADMIN=' /etc/backup.d/21_cbbackupmgr.sh 2>/dev/null | cut -d '"' -f 2)
            cb_pass=$(grep '^PASSWORD=' /etc/backup.d/21_cbbackupmgr.sh 2>/dev/null | cut -d '"' -f 2)
            if [ -z "$cb_user" ] || [ -z "$cb_pass" ]; then
                echo "UNKNOWN : Could not find couchbase admin and password"
            fi
            CHECK_COMMAND="/usr/local/nagios/plugins/check_cbbackupmgr.sh"
            BACKUP_DIR="/var/backups/couchbase_cbbackupmgr"
        else
            cb_user=$(grep -Eo '\-u ".*" \-p ".*"' /etc/backup.d/21_couchbase.sh 2>/dev/null | cut -d '"' -f 2)
            cb_pass=$(grep -Eo '\-u ".*" \-p ".*"' /etc/backup.d/21_couchbase.sh 2>/dev/null | cut -d '"' -f 4)
            if [ -z "$cb_user" ] || [ -z "$cb_pass" ]; then
                echo "UNKNOWN : Could not find couchbase admin and password"
            fi
            CHECK_COMMAND="/usr/local/nagios/plugins/check_younger_file_age.sh -w 24 -c 76 -d /var/backups/couchbase/"
            BACKUP_DIR="/var/backups/couchbase"
        fi
        if ! $LOCAL_ONLY; then
            # TODO couchbase-cli in PATH
            CLUSTER_HOSTS=$(/opt/couchbase/bin/couchbase-cli server-list -c localhost -u "$cb_user" -p "$cb_pass" | grep -v 'ERROR:' | cut -d ' ' -f 2 | cut -d ':' -f 1)
        fi
        ;;
    mongodb)
        CHECK_COMMAND="/usr/local/nagios/plugins/check_younger_file_age.sh -w 24 -c 76 -d /var/backups/mongodb/"
        BACKUP_DIR="/var/backups/mongodb"
        if ! $LOCAL_ONLY; then
            CLUSTER_HOSTS=$(sudo mongo --quiet --eval "JSON.stringify(rs.status())" | jq -r '.members[] | .name' | cut -d ':' -f 1)
            if [ "$(echo "$CLUSTER_HOSTS" | wc -w)" -eq 1 ]; then
                CLUSTER_HOSTS=""
            fi
        fi
        ;;
    ldap)
        CHECK_COMMAND='/usr/local/nagios/plugins/check_all_files_age.sh /var/backups/ldap'
        BACKUP_DIR="/var/backups/ldap"
        #CLUSTER_HOSTS='' # Not managed
        ;;
    elasticsearch)
        BACKUP_DIR="/var/backups/elasticsearch"
        elastic_user="$(grep '\-\-user' /etc/backup.d/21_elasticsearch.sh 2>/dev/null | cut -d ':' -f 1 | cut -d '"' -f 2)"
        elastic_pass="$(grep '\-\-user' /etc/backup.d/21_elasticsearch.sh 2>/dev/null | cut -d ':' -f 2 | cut -d '"' -f 1)"
        if [ -n "$elastic_user" ]; then
            CHECK_COMMAND="/usr/local/nagios/plugins/check_elasticsearch_backup.sh $elastic_user $elastic_pass"
        else
            CHECK_COMMAND="/usr/local/nagios/plugins/check_elasticsearch_backup.sh"
        fi
        #CLUSTER_HOSTS='' # Not managed
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
        if [ -f "${BACKUP_DIR}/README" ]; then
            cat "${BACKUP_DIR}/README"
            exit 0
        else
            echo "WARNING : Please document why backup_$1 is False in ${BACKUP_DIR}/README"
            exit 1
        fi
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
    echo "CRITICAL : Found $nb_oks OK $1 backups on $CLUSTER_HOSTS. We need at least $MIN_BACKUPS."
    exit 2
elif [ "$nb_oks" -gt "$MAX_BACKUPS" ]; then
    echo "WARNING : Found $1 backups on more than $MAX_BACKUPS host -" "${oks[@]}"
    exit 1
else
    echo "$last_ok_output on" "${oks[@]}"
    exit 0
fi
