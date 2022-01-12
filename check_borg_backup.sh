#!/bin/bash

MAX_BACKUPS=45 # 31 days + 12 months + some margin

export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes

WARN=24
CRIT=48
BORG_LIST=/var/backups/borglist.json
BORG_INFO=/var/backups/borginfo.json
WARN_NFILES=1000000
WARN_DURATION=3600

while getopts "w:c:n:f:d:" option
do
    case $option in
        w)
            WARN=$OPTARG
            ;;
        c)
            CRIT=$OPTARG
            ;;
        n)
            MAX_BACKUPS=$OPTARG
            ;;
        f)
            WARN_NFILES=$OPTARG
            ;;
        d)
            WARN_DURATION=$OPTARG
            ;;
        *)
            echo "Wrong argument"
            exit 3
            ;;
    esac
done

if [ "$WARN" -ge "$CRIT" ]; then
    echo "CRIT should be greater than WARN"
    exit 3
fi

warn_date="$(date +'%s' -d "-$WARN hour")"
crit_date="$(date +'%s' -d "-$CRIT hour")"

if ! [ -f $BORG_LIST ]; then
    echo "Could not found borg list file : $BORG_LIST"
    exit 3
fi

if ! [ -f $BORG_INFO ]; then
    echo "Could not found borg info file : $BORG_INFO"
    exit 3
fi

count=$(jq -r '.archives | length' $BORG_LIST)
last_date=$(date -d "$(jq -r '.archives[0].start' $BORG_INFO)" +%s)
last_name=$(jq -r '.archives[0].name' $BORG_INFO)
last_duration=$(jq -r '.archives[0].duration' $BORG_INFO | cut -d '.' -f 1)
nfiles=$(jq -r '.archives[0].stats.nfiles' $BORG_INFO)

msg="Last backup is $last_name"
total_size=$(jq -r '.cache.stats.total_size' $BORG_INFO)
unique_csize=$(jq -r '.cache.stats.unique_csize' $BORG_INFO)
unique_size=$(jq -r '.cache.stats.unique_size' $BORG_INFO)
total_size_gb=$(( total_size / 1024 / 1024 / 1024 ))
unique_size_gb=$(( unique_size / 1024 / 1024 / 1024 ))
unique_csize_gb=$(( unique_csize / 1024 / 1024 / 1024 ))
stats_msg="| total_size=${total_size_gb}GB;;;0; unique_size=${unique_size_gb}GB;;;0;  unique_size_compressed=${unique_csize_gb}GB;;;0; nfiles=${nfiles};;;0; duration=${last_duration};;;0;"

if [ "$last_date" -lt "$crit_date" ]; then
    echo "CRITICAL: $msg $stats_msg"
    exit 2
fi

if [ "$last_date" -lt "$warn_date" ]; then
    echo "WARNING: $msg $stats_msg"
    exit 1
fi

if [ "$count" -gt "$MAX_BACKUPS" ]; then
    echo "WARNING: $count backups, please check borg prune $stats_msg"
    exit 1
fi

if [ -n "$WARN_NFILES" ] && [ "$WARN_NFILES" -ne 0 ] && [ "$nfiles" -gt "$WARN_NFILES" ]; then
    echo "WARNING: $nfiles files in backup. Please check backup excludes. $stats_msg"
    exit 1
fi

if [ -n "$WARN_DURATION" ] && [ "$WARN_DURATION" -ne 0 ] && [ "$last_duration" -gt "$WARN_DURATION" ]; then
    echo "WARNING: last backup took more than $last_duration seconds. Please check backup excludes. $stats_msg"
    exit 1
fi

echo "OK: $msg $stats_msg" 
exit 0
