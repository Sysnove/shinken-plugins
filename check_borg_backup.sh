#!/bin/bash

MAX_BACKUPS=45 # 31 days + 12 months + some margin

export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes

REPOSITORY="backups:$(hostname)"
WARN=24
CRIT=48

while getopts "r:w:c:" option
do
    case $option in
        r)
            REPOSITORY="backups:$OPTARG"
            ;;
        w)
            WARN=$OPTARG
            ;;
        c)
            CRIT=$OPTARG
            ;;
        *)
    esac
done

if [ "$WARN" -ge "$CRIT" ]; then
    echo "CRIT should be greater than WARN"
    exit 3
fi

warn_date="$(date +'%s' -d "-$WARN hour")"
crit_date="$(date +'%s' -d "-$CRIT hour")"

if list=$(borg list "$REPOSITORY" --format="{name} {time}{NEWLINE}" 2>&1); then
    count=$(echo "$list" | wc -l)
    last=$(echo "$list" | tail -n 1)
    last_date=$(date -d "$(echo "$last" | cut -d ' ' -f2-)" +%s)
    last_name=$(echo "$last" | cut -d ' ' -f 1)

    msg="Last backup is $last_name"

    if [ ${#last_name} -eq 10 ]; then # We need to check that we don't have a -checkpoint backup
        if [ "$last_date" -gt "$warn_date" ]; then
            if [[ $count -gt $MAX_BACKUPS ]]; then
                echo "WARNING: $count backups, please check borg prune."
                exit 1
            else
                echo "OK: $msg" 
                exit 0
            fi
        elif [ "$last_date" -gt "$crit_date" ]; then
            echo "WARNING: $msg"
            exit 1
        fi
    fi

    echo "CRITICAL: $msg"
    exit 2
else
    echo "CRITICAL: $list" | head -n 1
    exit 2
fi
