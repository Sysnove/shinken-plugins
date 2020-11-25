#!/bin/bash

DIR="$1"

if [ -z "$DIR" ]; then
    echo "Usage: $0 DIRECTORY"
    exit 3
fi

if [ ! -d "$DIR" ]; then
    echo "CRITICAL : $DIR does not exist!"
    exit 2
fi

warnings=""
errors=""
oks=""

for f in $(find "$DIR" -maxdepth 1 -type f); do
    if [ -e /usr/lib64/nagios/plugins/check_file_age ] ; then
        /usr/lib64/nagios/plugins/check_file_age -w 90000 -c 180000 -f "$f" > /dev/null
    else
        /usr/lib/nagios/plugins/check_file_age -w 90000 -c 180000 -f "$f" > /dev/null
    fi
    ret=$?
    if [ $ret -gt 1 ]; then
        errors="$errors $f"
    elif [ $ret -eq 1 ]; then
        warnings="$warnings $f"
    else
        oks="$oks $f"
    fi
done

nb_ok="$(echo "$oks" | wc -w)"

if [ "$nb_ok" = 0 ]; then
    out="0 file up to date."
    ret=2
else
    out="$nb_ok files up to date. "
    ret=0

    if [ -n "$warnings" ]; then
        out="$(echo "$warnings" | wc -w) files WARNING ($warnings). ${out}"
        ret=1
    fi

    if [ -n "$errors" ]; then
        out="$(echo "$errors" | wc -w) files CRITICAL ($errors). ${out}"
        ret=2
    fi
fi

echo "$out"
exit $ret
