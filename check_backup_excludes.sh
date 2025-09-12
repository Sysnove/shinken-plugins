#!/bin/bash

#
# Check directories that should not be excluded from backups but could be by mistake
#

FORBIDDEN_EXCLUDES='^(sh:)?(/srv|/var|/var/(www|vmail|lib/docker|backups.*))/?$'
ALLOWED_EXCLUDES='BLAHBLAHBLAH'
# We need this exception for elasticsearch clusters where we need /var/backups/elasticsearch on all nodes, but we only need to backup it on the first node.
if ! [ -f /etc/backup.d/21_elasticsearch.sh ]; then
    ALLOWED_EXCLUDES='/var/backups/elasticsearch'
fi

backup_excludes=$(grep '^exclude =' /etc/backup.d/91_all.borg | awk '{print $3}')
backup_includes=$(grep '^include =' /etc/backup.d/91_all.borg | awk '{print $3}')

found_forbidden_excludes=$(echo "$backup_excludes" | grep -v "$ALLOWED_EXCLUDES" | grep -E "$FORBIDDEN_EXCLUDES" | tr '\n' ' ')
if [ -n "$found_forbidden_excludes" ]; then
    echo "CRITICAL - You should not exclude $found_forbidden_excludes (/srv, /var, /var/www, /var/vmail, /var/lib/docker or /var/backups/*)"
    exit 2
fi

#
# Check if files in / that are not included nor explicitely excluded
#

root_includes=$(sudo cat /etc/backup.d/91_all.borg | grep -E '^include = /[a-zA-Z0-9._-]+$' | cut -d ' ' -f 3 | tr '\n' '|' | sed 's/|$/\n/' | sed 's+/++g')
root_excludes=$(sudo cat /etc/backup.d/91_all.borg | grep -E '^exclude = (sh:)?/[a-zA-Z0-9._-]+$' | cut -d ' ' -f 3 | sed 's/sh://' | tr '\n' '|' | sed 's/|$/\n/' | sed 's+/++g')
nonroot_includes=$(sudo cat /etc/backup.d/91_all.borg | grep -E '^include = /[a-z0-9]+/.+' | cut -d ' ' -f 3 | tr '\n' '|' | sed 's/|$/\n/')
nonroot_excludes=$(sudo cat /etc/backup.d/91_all.borg | grep -E '^exclude = (sh:)?/[a-z0-9]+/.+' | cut -d ' ' -f 3 | sed 's/sh://' | tr '\n' '|' | sed 's/|$/\n/')
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
# Check database directories that should be in backup excludes
#

db_datadirs="/var/lib/postgresql /var/lib/mysql /var/lib/mongodb /var/lib/elasticsearch /opt/couchbase/var/lib/couchbase"
for d in $db_datadirs; do
    if ! echo "$backup_excludes" | grep -E -q "^(re:|sh:)?$d/?$"; then
        if [ -n "$(find "$d" -mindepth 1 -type d 2>/dev/null)" ]; then
            echo "WARNING - You should exclude $d from backups"
            exit 1
        fi
    fi
done

#
# Check SWAP files
#

swapfiles=$(swapon -s | grep file | awk '{print $1}')
for swapfile in $swapfiles; do
    if ! echo "$backup_excludes" | grep -E -q "^(re:|sh:)?$swapfile/?$"; then
        if ! echo "$backup_includes" | grep -E -q "^(re:|sh:)?$swapfile/?$"; then
            echo "WARNING - You should exclude $swapfile from backups"
            exit 1
        fi
    fi
done

#
# Check bind and network mounts that should be in backup excludes
#

bind_missing=""

bind_mount_sources=$(grep bind /etc/fstab | grep -v '^/var/log' | awk '{print $1}' | grep -v '^#')
for mount_source in $bind_mount_sources; do
    if ! echo "$backup_excludes" | grep -E -q "^(re:|sh:)?$mount_source/?$"; then
        if ! echo "$backup_includes" | grep -E -q "^(re:|sh:)?$mount_source/?$"; then
            if ! grep -q "^#include_bind_mount_source = $mount" /etc/backup.d/91_all.borg; then
                bind_missing="$bind_missing$mount_source "
            fi
        fi
    fi
done

if [ -n "$bind_missing" ]; then
    echo "WARNING - You should run backups.yml or explicitely include bind mount sources from backups: $bind_missing"
    exit 1
fi

network_missing=""

nfs_mounts=$(grep ' nfs ' /etc/fstab  | grep -v '^#' | awk '{print $2}')
for mount in $nfs_mounts; do
    if ! echo "$backup_excludes" | grep -E -q "^(re:|sh:)?$mount/?$"; then
        if ! echo "$backup_includes" | grep -E -q "^(re:|sh:)?$mount/?$"; then
            if ! grep -q "^#include_network_mount = $mount" /etc/backup.d/91_all.borg; then
                network_missing="$network_missing$mount "
            fi
        fi
    fi
done

sshfs_mounts=$(grep '^sshfs#' /etc/fstab | grep -v '^#'| awk '{print $2}')
for mount in $sshfs_mounts; do
    if ! echo "$backup_excludes" | grep -E -q "^(re:|sh:)?$mount/?$"; then
        if ! echo "$backup_includes" | grep -E -q "^(re:|sh:)?$mount/?$"; then
            if ! grep -q "^#include_network_mount = $mount" /etc/backup.d/91_all.borg; then
                network_missing="$network_missing$mount "
            fi
        fi
    fi
done

if [ -n "$network_missing" ]; then
    echo "WARNING - You should exclude or explicitely include network mounts from backups: $network_missing"
    exit 1
fi


echo "Everything seems to be backed up."
exit 0
