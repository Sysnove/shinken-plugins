#!/bin/bash

MAX_BACKUPS=45 # 31 days + 12 months + some margin

export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes

REPOSITORY="backups:$(hostname)"
THRESHOLD=0

while getopts "r:t:" option
do
    case $option in
        r)
            REPOSITORY="backups:$OPTARG"
            ;;
        t)
            THRESHOLD=$OPTARG
            ;;
        *)
    esac
done

ok_date="$(date +'%Y-%m-%d' -d "-$THRESHOLD day")"
warn_date="$(date +'%Y-%m-%d' -d "-$((THRESHOLD + 1)) day")"

if list=$(borg list --short "$REPOSITORY" 2>&1); then
    last=$(echo "$list" | tail -n 1)
    count=$(echo "$list" | wc -l)

    msg="Last backup is $last"

    if [[ "$last" == "$ok_date" ]]; then
        if [[ $count -gt $MAX_BACKUPS ]]; then
            echo "WARNING: $count backups, please check borg prune."
            exit 1
        else
            echo "OK: $msg" 
            exit 0
        fi
    elif [[ "$last" == "$warn_date" ]]; then
        echo "WARNING: $msg"
        exit 1
    else
        echo "CRITICAL: $msg"
        exit 2
    fi
else
    echo "CRITICAL: $list" | head -n 1
    exit 2
fi
