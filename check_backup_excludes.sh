#!/bin/sh

FORBIDDEN_EXCLUDES='^/var/(www|vmail|backups|lib/docker)$'

backup_excludes=$(cat /etc/backup.d/90.borg | grep '^exclude =' | awk '{print $3}')
bind_mounts=$(cat /etc/fstab | grep bind | grep -v '^/var/log' | awk '{print $1}')


if echo "$backup_excludes" | egrep -q $FORBIDDEN_EXCLUDES; then
    echo "CRITICAL - You should not exclude $FORBIDDEN_EXCLUDES"
    exit 2
fi

missing=""

for source in $bind_mounts; do
    if ! echo "$backup_excludes" | egrep -q "^$source$"; then
        missing="$missing$source "
    fi
done

if [ ! -z "$missing" ]; then 
    echo "WARNING - You should exclude following path from backups: $missing"
    exit 1
else
    echo "OK - Backup excludes seems to be well configured"
    exit 0
fi
