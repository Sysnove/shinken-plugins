#!/bin/sh

pid=$(pgrep -a -x glusterfs | grep /srv/docker-data | cut -d ' ' -f 1)

if [ -z "$pid" ] ; then
    echo "UNKNOWN : Unable to find glusterfs pid. Is it running?"
    return 3
fi

mem=$(cat /proc/$pid/status | grep VmRSS | awk '{print $2}')

echo "GlusterFS Memory : ${mem}kB | memory=${mem}kB"
