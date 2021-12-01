#!/bin/bash

MAX_BACKUPS=45 # 31 days + 12 months + some margin
BORG_TIMEOUT=55

export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes

REPOSITORY="backups:$(hostname)"
WARN=24
CRIT=48

while getopts "r:w:c:n:" option
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
        n)
            MAX_BACKUPS=$OPTARG
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

# Abort if we are too close from backupninja, to avoid locking borg repository
if pgrep -f /usr/sbin/backupninja > /dev/null; then
    echo "UNKNOWN : Avoiding to run the check during backupninja execution."
    exit 3
fi

backupninja_when="$(grep '^when =' /etc/backupninja.conf | cut -d '=' -f 2)"

if echo "$backupninja_when" | grep -q '^ everyday at'; then
    backupninja_hour=$(echo "$backupninja_hour" | cut -d ' ' -f 4)
    if [ "$(date --date 'now + 1 minutes' +%H:%M)" == "$backupninja_hour" ] || [ "$(date +%H:%M)" == "$backupninja_hour" ]; then
        echo "UNKNOWN : Avoiding to run the check one minute before backupninja"
        exit 3
    fi
elif [ "$backupninja_when" == ' hourly' ]; then
    if [ "$(date --date 'now + 1 minutes' +%M)" -eq 0 ] || [ "$(date +%M)" -eq 0 ]; then
        echo "UNKNOWN : Avoiding to run the check one minute before backupninja"
        exit 3
    fi
else
    echo "UNKNOWN : Could not parse 'when' variable in /etc/backupninja.conf"
    exit 3
fi

# Check last backup
if list=$(timeout $BORG_TIMEOUT borg list "$REPOSITORY" --format="{name} {time}{NEWLINE}" 2>&1); then
    count=$(echo "$list" | wc -l)
    last=$(echo "$list" | tail -n 1)
    last_date=$(date -d "$(echo "$last" | cut -d ' ' -f2-)" +%s)
    last_name=$(echo "$last" | cut -d ' ' -f 1)

    msg="Last backup is $last_name"

    if [ ${#last_name} -eq 10 ] || [ ${#last_name} -eq 13 ]; then # We need to check that we don't have a "-checkpoint" backup
        if [ "$last_date" -gt "$warn_date" ]; then
            if [[ $count -gt $MAX_BACKUPS ]]; then
                echo "WARNING: $count backups, please check borg prune."
                exit 1
            else
                if stats=$(timeout 5 borg info "$REPOSITORY" --json | jq -r .cache.stats); then
                    #total_chunks=$(echo "$stats" | jq -r '.total_chunks')
                    #total_csize=$(echo "$stats" | jq -r '.total_csize')
                    total_size=$(echo "$stats" | jq -r '.total_size')
                    #total_unique_chunks=$(echo "$stats" | jq -r '.total_unique_chunks')
                    unique_csize=$(echo "$stats" | jq -r '.unique_csize')
                    unique_size=$(echo "$stats" | jq -r '.unique_size')
                    total_size_gb=$(( total_size / 1024 / 1024 / 1024 ))
                    unique_size_gb=$(( unique_size / 1024 / 1024 / 1024 ))
                    unique_csize_gb=$(( unique_csize / 1024 / 1024 / 1024 ))
                    stats_msg="| total_size=${total_size_gb}GB;;;0; unique_size=${unique_size_gb}GB;;;0;  unique_size_compressed=${unique_csize_gb}GB;;;0;"
                else
                    stats_msg="(but could not retrieve stats)"
                fi
                echo "OK: $msg $stats_msg" 
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
    if [ $? -eq 124 ]; then
        echo "borg list did not return before $BORG_TIMEOUT seconds."
        exit 3
    else
        echo "CRITICAL: $list" | head -n 1
        exit 2
    fi
fi
