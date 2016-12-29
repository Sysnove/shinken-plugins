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

for f in $(ls $DIR); do
    /usr/lib/nagios/plugins/check_file_age -w 90000 -c 180000 -f $DIR/$f > /dev/null
    ret=$?
    if [ $ret -gt 1 ]; then
        errors="$errors $f"
    elif [ $ret -eq 1 ]; then
        warnings="$warnings $f"
    else
        oks="$oks $f"
    fi
done

out="$(echo $oks | wc -w) files up to date. "
ret=0

if [ ! -z "$warnings" ]; then
    out="$(echo $warnings | wc -w) files WARNING ($warnings). ${out}"
    ret=1
fi

if [ ! -z "$errors" ]; then
    out="$(echo $errors | wc -w) files CRITICAL ($errors). ${out}"
    ret=2
fi

echo "$out"
exit $ret
