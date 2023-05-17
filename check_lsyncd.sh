#!/bin/bash

# Warning : This is very ugly and does not read lua properly
# Other option, one script per sync

ret=0

check_lsync() {
    src=$1
    target=$2

    mkdir -p "$src/.test"
    date > "$src/.test/date"
    datenow=$(date -r "$src/.test/date" +%s)
    target_host=$(echo "$target" | cut -d ':' -f 1)
    target_dir=$(echo "$target" | cut -d ':' -f 2)
    # shellcheck disable=SC2034
    for i in {1..5}; do
        if datetarget=$(ssh -n "$target_host" "date -r $target_dir/.test/date +%s"); then
            lag=$((datenow - datetarget))
            if [ $lag -eq 0 ]; then
                break
            fi
            sleep 1
        else
            exit 3
        fi
    done

    if [ "$lag" -gt 3200 ]; then
        retmsg="CRITICAL"
        ret=2
    elif [ "$lag" -gt 600 ] && [ $ret -lt 2 ]; then
        retmsg="WARNING"
        ret=1
    else
        retmsg="OK"
    fi

    echo "$retmsg - Last sync to $target was $lag seconds ago."

    if [ $ret -ne 0 ]; then
        exit $ret
    fi
}

pids=""
while IFS="" read -r line; do
    if echo "$line" | grep -q 'source ='; then
        src=$(echo "$line" | cut -d "'" -f 2)
    elif echo "$line" | grep -q 'target ='; then
        target=$(echo "$line" | cut -d "'" -f 2)
    elif echo "$line" | grep -q 'sync {'; then
        src=""
        target=""
    fi
    if [ -n "$src" ] && [ -n "$target" ]; then
        check_lsync $src $target &
        pids+=" $!"
        src=""
        target=""
    fi
done < /etc/lsyncd/lsyncd.conf.lua

ret=0
for p in $pids; do
    wait $p
    p_ret=$?
    if [ $p_ret -gt $ret ]; then
        ret=$p_ret
    fi
done

exit $ret
