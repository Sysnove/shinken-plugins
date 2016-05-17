#!/bin/zsh

export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes

if [ -z $1 ]; then
    repository="backups:$(hostname)"
else
    repository="backups:$1"
fi

list=$(borg list --short $repository 2>&1)

if [ $? = 0 ]; then
    last=$(echo $list | tail -n 1)
    stats=$(borg info $repository::$last 2> /dev/null | grep "^This archive")
    compressed_size=$(echo "$stats" | awk '{print $5 $6}')
    dedup_size=$(echo "$stats" | awk '{print $7 $8}')

    msg="Last backup is $last ($compressed_size used). | compressed_size=$compressed_size; dedup_size=$dedup_size;"

    if [[ "$last" == "$(date +'%Y-%m-%d')" ]]; then
        echo "OK: $msg" 
        exit 0
    elif [[ "$last" == "$(date +'%Y-%m-%d' -d "yesterday")" ]]; then
        echo "WARNING: $msg"
        exit 1
    else
        echo "CRITICAL: $msg"
        exit 2
    fi
else
    # Unable to connect
    # CRITICAL
    echo "CRITICAL: $list" | head -n 1
    exit 2
fi
