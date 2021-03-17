#!/bin/sh

#
# Check directories that should not be excluded from backups but could be by mistake
#

FORBIDDEN_EXCLUDES='^/var/(www|vmail|backups|lib/docker)$'

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
other_excludes=$(sudo cat /etc/backup.d/90.borg | grep -E '^exclude = (sh:)?/[a-z0-9]+/' | cut -d ' ' -f 3 | sed 's/sh://' | tr '\n' '|' | sed 's/|$/\n/')

shopt -s nullglob dotglob

# shellcheck disable=SC2010
for d in $(ls / | grep -Ev "^($root_includes|$root_excludes|lost\\+found|dev|proc|sys|run|tmp|clean|core|ansible-runs\.log|sigs)$" | grep -Ev '^(vmlinuz|initrd|netdata-updater.log|maldet-)'); do
    if ! mount | grep "/$d" | grep -q '^borgfs'; then
        if find "/$d" -type f | grep -qEv "^($other_excludes)"; then
            echo "CRITICAL - Unbackuped files found in /$d !"
            exit 3
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
