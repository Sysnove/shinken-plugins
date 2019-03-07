#!/bin/sh

if [ -d /etc/glusterfs ] ;
    pid=$(pgrep -a -x glusterfs | grep /srv/docker-data | cut -d ' ' -f 1)

    if [ -z "$pid" ] ; then
        echo "UNKNOWN : Unable to find glusterfs pid. Is it running?"
        exit 3
    fi

    mem=$(cat /proc/$pid/status | grep VmRSS | awk '{print $2}')

    echo "GlusterFS Memory : ${mem}kB | memory=${mem}kB"
else
    echo "This is not a GlusterFS client."
fi

