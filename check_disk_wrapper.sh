#!/bin/bash

# This wrapper manages default exclusions on check_disk.
# The last part $(findmnt…) adds exclusions for bind mounts.

if [ -x /usr/lib/nagios/plugins/check_disk ] ; then
    exe=/usr/lib/nagios/plugins/check_disk
elif [ -x /usr/lib64/nagios/plugins/check_disk ] ; then
    exe=/usr/lib64/nagios/plugins/check_disk
else
    exit "Could not find check_disk executable."
    exit 3
fi

$exe $@ -I '^/sys' -I '^/run' -I '^/dev$' -I tmpfs -I borgfs -X tmpfs -X fuse.sshfs -X fuse.nvim -X devtmpfs -X aufs -X overlay -X overlay2 $(findmnt --raw | grep '\[' | awk '{print "-I "$1}' | xargs)

exit $?
