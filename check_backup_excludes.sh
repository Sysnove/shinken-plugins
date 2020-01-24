#!/bin/sh


if [ -z "$1" ] ; then
    FORBIDDEN_EXCLUDES='^/var/(www|vmail|backups|lib/docker)$'
else
    FORBIDDEN_EXCLUDES="$1"
fi

backup_excludes=$(cat /etc/backup.d/90.borg | grep '^exclude =' | awk '{print $3}')
bind_mounts=$(cat /etc/fstab | grep bind | grep -v '^/var/log' | awk '{print $1}' | grep -v '^#')


if echo "$backup_excludes" | egrep -q $FORBIDDEN_EXCLUDES; then
    echo "CRITICAL - You should not exclude /var/www, /var/vmail, /var/backups or /var/lib/docker"
    exit 2
fi

missing=""

for source in $bind_mounts; do
    if ! echo "$backup_excludes" | egrep -q "^(re:|sh:)?$source$"; then
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
