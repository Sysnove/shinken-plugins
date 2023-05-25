#!/bin/bash

DIR="$1"
FINDOPTS="$2"
MMIN_WARN="$3"
[ -z "$MMIN_WARN" ] || MMIN_WARN=1500
MMIN_CRIT="$4"
[ -z "$MMIN_CRIT" ] || MMIN_CRIT=3000

if [ -z "$DIR" ]; then
    echo "Usage: $0 DIRECTORY"
    exit 3
fi

if [ ! -d "$DIR" ]; then
    echo "CRITICAL : $DIR does not exist!"
    exit 2
fi

if [ -n "$FINDOPTS" ]; then
    FIND="find $DIR $FINDOPTS -type f -not -name README.txt -not -name README"
else
    FIND="find $DIR -type f -not -name README.txt -not -name README"
fi

warnings=$($FIND -mmin +$MMIN_WARN -mmin -$MMIN_CRIT)
errors=$($FIND  -mmin +$MMIN_CRIT)
oks=$($FIND -mmin -$MMIN_WARN)

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
