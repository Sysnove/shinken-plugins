#!/bin/sh

mem=$(cat /proc/$(pgrep -u root glusterfs)/status | grep VmRSS | awk '{print $2}')

echo "GlusterFS Memory : ${mem}kB | memory=${mem}kB"
