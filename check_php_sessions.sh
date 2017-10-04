#!/bin/bash

total=$(nice -n 19 find / -name 'sess_*' -ctime +15 2>/dev/null | grep -v /usr/share/man/man1/sess_id.1ssl.gz | wc -l)

msg="$total PHP old session files found | total=$total;;;;;"

if [ $total -lt 10000 ] ; then
    echo "OK: $msg"
    exit 0
else
    echo "WARNING: $msg"
    exit 1
fi
