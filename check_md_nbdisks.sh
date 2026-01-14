#!/bin/sh

# shellcheck disable=SC2013
for md in $(cat /proc/mdstat | grep -oE '^md[0-9]'); do
    disks=$(cat /proc/mdstat | grep "^$md" | grep -oE '(hd|sd|nvme).+')
    nb_disks=$(echo "$disks" | wc -w)
    if [ "$nb_disks" -lt 2 ]; then
        echo "CRITICAL - $md RAID is made of $nb_disks disks: $disks"
        exit 2
    fi
done

echo "OK - All md raids at made of at least 2 disks."
exit 0
