#!/bin/sh

total_k=$(grep MemTotal /proc/meminfo | awk '{print $2}')
slab_unreclaim_k=$(grep SUnreclaim /proc/meminfo | awk '{print $2}')

total_m=$((total_k / 1024))
slab_unreclaim_m=$((slab_unreclaim_k / 1024))

slab_unreclaim_pct=$(((100 * slab_unreclaim_m) / total_m))

echo "SlabUnreclaim ${slab_unreclaim_m}MB (${slab_unreclaim_pct}%)|sunreclaim=${slab_unreclaim_pct}MB;;;0;$total_m"
exit 0

