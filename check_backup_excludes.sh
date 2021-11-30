#!/bin/bash

#
# Check directories that should not be excluded from backups but could be by mistake
#

FORBIDDEN_EXCLUDES='^(sh:)?(/srv|/var|/var/(www|vmail|backups|lib/docker))$'

backup_excludes=$(grep '^exclude =' /etc/backup.d/90.borg | awk '{print $3}')
bind_mounts=$(grep bind /etc/fstab | grep -v '^/var/log' | awk '{print $1}' | grep -v '^#')


if echo "$backup_excludes" | grep -E -q "$FORBIDDEN_EXCLUDES"; then
    echo "CRITICAL - You should not exclude /var/www, /var/vmail, /var/backups or /var/lib/docker"
    exit 2
fi

#
# Check if files in / that are not included nor explicitely excluded
#

root_includes=$(sudo cat /etc/backup.d/90.borg | grep -E '^include = /[a-z0-9\.]+$' | cut -d ' ' -f 3 | tr '\n' '|' | sed 's/|$/\n/' | sed 's+/++g')
root_excludes=$(sudo cat /etc/backup.d/90.borg | grep -E '^exclude = (sh:)?/[a-z0-9\.]+$' | cut -d ' ' -f 3 | sed 's/sh://' | tr '\n' '|' | sed 's/|$/\n/' | sed 's+/++g')
nonroot_includes=$(sudo cat /etc/backup.d/90.borg | grep -E '^include = /[a-z0-9]+/.+' | cut -d ' ' -f 3 | tr '\n' '|' | sed 's/|$/\n/')
nonroot_excludes=$(sudo cat /etc/backup.d/90.borg | grep -E '^exclude = (sh:)?/[a-z0-9]+/.+' | cut -d ' ' -f 3 | sed 's/sh://' | tr '\n' '|' | sed 's/|$/\n/')
if [ -n "$nonroot_includes" ] && [ -n "$nonroot_excludes" ]; then
    nonroot_regex="($nonroot_excludes|$nonroot_includes)"
elif [ -n "$nonroot_includes" ]; then
    nonroot_regex="($nonroot_includes)"
elif [ -n "$nonroot_excludes" ]; then
    nonroot_regex="($nonroot_excludes)"
else
    nonroot_regex=""
fi

shopt -s nullglob dotglob
IFS=$'\n'

for d in $(find / -maxdepth 1 -mindepth 1 | grep -Ev "^/($root_includes|$root_excludes|lost\\+found|dev|proc|sys|run|tmp|clean|core|ansible-runs\.log|sigs|.postgresql_anti_restart_guard_file|.autorelabel)$" | grep -Ev '^/(vmlinuz|initrd|netdata-updater|netdata-updater.log|maldet-)'); do
    if ! mount | grep "$d" | grep -q '^borgfs'; then
        if [ -f "$d" ]; then
            if echo "$d" | grep -qEv "^$nonroot_regex"; then
                echo "CRITICAL - Unbackuped file $d !"
                exit 2
            fi
        else
            for d2 in $(find "$d" -mindepth 1 -maxdepth 1 | grep -Ev "^$nonroot_regex$"); do
                if find "$d2" -type f | grep -qEv "^$nonroot_regex"; then
                    echo "CRITICAL - Unbackuped files found in $d !"
                    exit 2
                fi
            done
        fi
    fi
done

#
# Check bind mounts that should be in backup excludes
#

missing=""

for source in $bind_mounts; do
    if ! echo "$backup_excludes" | grep -E -q "^(re:|sh:)?$source/?$"; then
        missing="$missing$source "
    fi
done

if [ -n "$missing" ]; then 
    echo "WARNING - You should exclude following path from backups: $missing"
    exit 1
fi


echo "Everything seems to be backed up."
exit 0
