#!/bin/sh

repository="backups:$(hostname)"

borg info $repository::$(date +'%Y-%m-%d') > /dev/null 2>&1

if [ $? = 0 ]; then
    # OK
    echo "OK: Last backup is $(date +'%Y-%m-%d')"
    return 0
else
    borg info $repository::$(date +'%Y-%m-%d' -d "yesterday") > /dev/null 2>&1
    if [ $? = 0 ]; then
        # WARNING
        echo "WARNING: Last backup is $(date +'%Y-%m-%d' -d 'yesterday')"
        return 1
    else
        list=$(borg list --short $repository 2>&1)
        if [ $? = 0 ]; then
            last=$(echo $list | tail -n 1)
            # Last backup is $last
            # CRITICAL
            echo "CRITICAL: Last backup is $last."
            return 2
        else
            # Unable to connect
            # CRITICAL
            echo "CRITICAL: $list" | head -n 1
            return 2
        fi
    fi
fi
