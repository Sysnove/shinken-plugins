#!/bin/zsh

if [ -z $1 ]; then
    repository="backups:$(hostname)"
else
    repository="backups:$1"
fi

list=$(borg list --short $repository 2>&1)

if [ $? = 0 ]; then
    if echo $list | grep -q "^$(date +'%Y-%m-%d')$"; then
        # OK
        echo "OK: Last backup is $(date +'%Y-%m-%d')"
        exit 0
    elif echo $list | grep -q "^$(date +'%Y-%m-%d' -d "yesterday")$"; then
        # WARNING
        echo "WARNING: Last backup is $(date +'%Y-%m-%d' -d 'yesterday')"
        exit 1
    else
        last=$(echo $list | tail -n 1)
        # Last backup is $last
        # CRITICAL
        echo "CRITICAL: Last backup is $last."
        exit 2
    fi
else
    # Unable to connect
    # CRITICAL
    echo "CRITICAL: $list" | head -n 1
    exit 2
fi
