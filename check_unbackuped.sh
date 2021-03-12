#!/bin/bash

includes=$(sudo cat /etc/backup.d/90.borg | grep -E '^include = /[a-z0-9]+' | cut -d ' ' -f 3 | tr '\n' '|' | sed 's/|$/\n/' | sed 's+/++g')

shopt -s nullglob dotglob

# shellcheck disable=SC2010
for d in $(ls / | grep -Ev "^($includes|lost\\+found|dev|proc|sys|run|tmp|clean)$" | grep -Ev '^(vmlinuz|initrd)'); do
    if [ -n "$(find "/$d" -type f)" ]; then
        echo "Unbackuped files found in /$d !"
        exit 3
    fi
done

echo "Everything seems to be backed up."
exit 0
