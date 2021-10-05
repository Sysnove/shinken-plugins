#!/bin/bash

for v in $(gluster volume list); do
    if ! mount | grep -q "^localhost:$v on /srv/gluster-backup/$v type fuse.glusterfs"; then
        echo "CRITICAL : /srv/gluster-backup/$v is not mounted"
        exit 2
    fi
    if ! grep -q "^localhost:$v /srv/gluster-backup/$v glusterfs" /etc/fstab; then
        echo "CRITICAL : /srv/gluster-backup/$v is not in fstab"
        exit 2
    fi
done

echo "All volumes are correctly mounted in /srv/gluster-backup"
