#!/bin/bash

MAX=$(sysctl -n fs.inotify.max_user_instances)

WARN=80
CRIT=90

WARN_THRESHOLD=$((MAX*WARN/100))
CRIT_THRESHOLD=$((MAX*CRIT/100))

ret=0
msg="OK - fs.inotify.max_user_instances=$MAX"
root_count=0

IFS=$'\n'


function foo {
    for line in $(find /proc/*/fd/* -type l -lname 'anon_inode:inotify' -print 2>/dev/null | cut -d/ -f3 | sort | uniq -c); do
        count=$(echo $line | awk '{print $1}')
        user=$(echo $line | awk '{print $2}' | xargs ps --no-headers -o '%U' -p)
        echo $count $user
    done
}

for i in $(foo | awk '{a[$2] += $1} END{for (i in a) print a[i], i}' | sort -nr); do
    count=$(echo $i | sed -e 's/^[ \t]*//' | awk '{print $1}')
    name=$(echo $i | sed -e 's/^[ \t]*//' | awk '{print $2}')
    if [ $count -gt $WARN_THRESHOLD -a $ret -lt 2 ]; then
        msg="WARNING - $name user has $count inotify open (Max=$MAX)"
        ret=1
    fi
    if [ $count -gt $CRIT_THRESHOLD ]; then
        msg="CRITICAL - $name user has $count inotify open (Max=$MAX)"
        ret=2
    fi

    if [ "$name" = 'root' ]; then
        root_count=$count
    fi
done

echo "$msg | root_inotify_instances=$root_count;$WARN_THRESHOLD;$CRIT_THRESHOLD;0;$MAX;"
ret=0

