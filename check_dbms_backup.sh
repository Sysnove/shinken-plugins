#!/bin/bash

###
### This plugins checks if there is an up to date backup for various database management systems.
### On replicated clusters, it will check every server and count the number of backups.
### By default we want one backup. Not less, but not much.
###
### Usage: check_dbms_backup.sh --type (postgresql|mysql|couchbase|mongodb|…) [--max 1]
###


MAX_BACKUPS=1

case $1 in
    --postgresql)
        CHECK_COMMAND="/usr/local/nagios/plugins/check_all_files_age.sh /var/backups/postgres"
        CLUSTER_HOSTS=$(sudo -u postgres repmgr cluster show 2>&1 | grep -o 'host=[^ ]*' | cut -d '=' -f 2)
        ;;
    --mysql)
        CHECK_COMMAND="/usr/local/nagios/plugins/check_all_files_age.sh /var/backups/mysql/sqldump"
        CLUSTER_HOSTS=$(sudo mysql --skip-column-names -sr -e "show slave hosts;" | awk '{print $2}')
        ;;
    --couchbase)
        ;;
    --mongodb)
        ;;
    #--lsync)
        #CHECK_COMMAND="grep 'backup_excludes: /srv/***$' /etc/backup.d/91.borg"
        #HOSTS=""
        #;;
    *)
        echo "$1 is not managed"
        exit 3
        ;;
esac

if [ "$2" == '--max' ]; then
    MAX_BACKUPS="$3"
fi

oks=()
noks=()
for host in $CLUSTER_HOSTS; do
    # shellcheck disable=SC2029
    output=$(ssh -oStrictHostKeyChecking=no "$host" "$CHECK_COMMAND" 2>&1)
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

if [ "$nb_oks" -eq 0 ]; then
    #echo "CRITICAL : No backup found on" "${noks[@]}"
    #exit 2
    # return result of local check
    $CHECK_COMMAND
    exit $?
elif [ "$nb_oks" -le "$MAX_BACKUPS" ]; then
    echo "OK : $last_ok_output on" "${oks[@]}"
    exit 0
else
    echo "WARNING : Found backups on more than $MAX_BACKUPS host -" "${oks[@]}"
    exit 1
fi
