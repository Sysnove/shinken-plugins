#!/bin/sh

/usr/bin/df -i | tail -n +2 | while read -r line; do
    mount="$(echo "$line" | awk '{print $NF}')"
    inodes="$(echo "$line" | awk '{print $3}')"

    if [ "$inodes" -gt 10000000 ]; then
        echo "WARNING : $mount contains $inodes files"
        exit 2
    fi
done

echo "OK : No partition over 10M files"
exit 0
