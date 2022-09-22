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

if [ "$2" == "--maxdepth" ]; then
    FINDOPT="-maxdepth $3"
fi

FIND=(find "$DIR" "$FINDOPT" -type f -not -name "README.txt")

warnings=$("${FIND[@]}" -mmin +1500 -mmin -3000)
errors=$("${FIND[@]}" -mmin +3000)
oks=$("${FIND[@]}" -mmin -1500)

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
