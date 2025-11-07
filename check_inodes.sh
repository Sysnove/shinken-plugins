#!/bin/bash

THRESHOLD=$1

[ -z "$THRESHOLD" ] && THRESHOLD=10000000

ret_code=0

while read -r line; do
    mount="$(echo "$line" | awk '{print $NF}')"
    inodes="$(echo "$line" | awk '{print $3}')"

    if [ "$inodes" -gt "$THRESHOLD" ]; then
        echo "WARNING : $mount contains $inodes files"
        ret_code=1
    fi
done < <(/usr/bin/df -i | tail -n +2)

if [ "$ret_code" -eq 0 ]; then
    echo "OK : No partition over $THRESHOLD files"
fi

exit $ret_code
