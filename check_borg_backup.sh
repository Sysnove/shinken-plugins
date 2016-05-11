#!/bin/sh

repository="backups:/srv/backups/sysnove/borg/$(hostname)"

sudo borg info $repository::$(date +'%Y-%m-%d') > /dev/null

if [ $? = 0 ]; then
    # OK
    echo "OK"
else
    sudo borg info $repository::$(date +'%Y-%m-%d' -d "yesterday") > /dev/null 2>&1
    if [ $? = 0 ]; then
        # WARNING
        echo "WARNING"
    else
        list=$(sudo borg list --short $repository)
        if [ $? = 0 ]; then
            last=$(echo $list | tail -n 1)
            # Last backup is $last
            # CRITICAL
            echo "CRITICAL: Last backup is $last."
        else
            # Unable to connect
            # CRITICAL
            echo "CRITICAL: $list"
        fi
    fi
fi
