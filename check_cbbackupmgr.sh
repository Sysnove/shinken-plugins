#!/bin/bash


AGE_CRITICAL_THRESHOLD=3
AGE_WARNING_THRESHOLD=1

ARCHIVE_DIR="/var/backups/couchbasemgr"
REPO_NAME="cluster"

if ! [ -r "$ARCHIVE_DIR/$REPO_NAME" ]; then
    echo "UNKNOWN - $ARCHIVE_DIR/$REPO_NAME is not readable."
    exit 3
fi

cbbackupmgr_info="$(/opt/couchbase/bin/cbbackupmgr info --archive $ARCHIVE_DIR --repo $REPO_NAME --json)"

last_complete_backup=$(echo "$cbbackupmgr_info" | jq -r '.backups[] | select(.complete==true) | .date' | sort | tail -n 1)

if [ -z "$last_complete_backup" ]; then
    echo "CRITICAL - No complete cbbackupmgr backup found."
    exit 2
fi

last_complete_backup_ts=$(date -d "$(echo "$last_complete_backup" | sed 's/_/:/g' | sed 's/\..*//' | sed 's/T/ /g')" +%s)
now=$(date +'%s')
age_in_seconds=$((now - last_complete_backup_ts))
age_in_days=$((age_in_seconds / (24*3600)))

if [ "$age_in_days" -gt $AGE_CRITICAL_THRESHOLD ]; then
    echo "CRITICAL - Last cbbackupmgr backup is older than $AGE_CRITICAL_THRESHOLD days."
    exit 2
fi

if [ "$age_in_days" -gt $AGE_WARNING_THRESHOLD ]; then
    echo "WARNING - Last cbbackupmgr backup is older than $AGE_WARNING_THRESHOLD day."
    exit 1
fi

echo "OK - Last cbbackupmgr backup is $last_complete_backup"
exit 1
