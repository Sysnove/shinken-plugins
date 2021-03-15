#!/bin/bash

root_includes=$(sudo cat /etc/backup.d/90.borg | grep -E '^include = /[a-z0-9\.]+$' | cut -d ' ' -f 3 | tr '\n' '|' | sed 's/|$/\n/' | sed 's+/++g')
root_excludes=$(sudo cat /etc/backup.d/90.borg | grep -E '^exclude = /[a-z0-9\.]+$' | cut -d ' ' -f 3 | tr '\n' '|' | sed 's/|$/\n/' | sed 's+/++g')
other_excludes=$(sudo cat /etc/backup.d/90.borg | grep -E '^exclude = (sh:)?/[a-z0-9]+/' | cut -d ' ' -f 3 | sed 's/sh://' | tr '\n' '|' | sed 's/|$/\n/')

shopt -s nullglob dotglob

# shellcheck disable=SC2010
for d in $(ls / | grep -Ev "^($root_includes|$root_excludes|lost\\+found|dev|proc|sys|run|tmp|clean|core|ansible-runs\.log)$" | grep -Ev '^(vmlinuz|initrd)'); do
    if ! mount | grep "/$d" | grep -q '^borgfs'; then
        if find "/$d" -type f | grep -qEv "^($other_excludes)"; then
            echo "Unbackuped files found in /$d !"
            exit 3
        fi
    fi
done

echo "Everything seems to be backed up."
exit 0
