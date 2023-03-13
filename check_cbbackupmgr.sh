#!/bin/bash


AGE_CRITICAL_THRESHOLD=$((3 * 24 * 3600))
AGE_WARNING_THRESHOLD=$((24 * 3600))

ARCHIVE_DIR="/var/backups/couchbase_cbbackupmgr"
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
age=$((now - last_complete_backup_ts))

if [ "$age" -gt $AGE_CRITICAL_THRESHOLD ]; then
    echo "CRITICAL - Last cbbackupmgr backup is older than $((AGE_CRITICAL_THRESHOLD / (24 * 3600))) days."
    exit 2
fi

if [ "$age" -gt $AGE_WARNING_THRESHOLD ]; then
    echo "WARNING - Last cbbackupmgr backup is older than $((AGE_WARNING_THRESHOLD / (24 * 3600))) day."
    exit 1
fi

echo "OK - Last cbbackupmgr backup is $last_complete_backup"
exit 0
