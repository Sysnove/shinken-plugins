#!/bin/bash

WARN=$1
[ -z "$WARN" ] && WARN=10
WARN=$((WARN * 1000000000))

# Always good to set the PATH in a cron script
export PATH=/usr/local/bin:/usr/bin:/bin
# Avoid locale interpretation in numfmt.
export LC_ALL=C

DF_OUTPUT=$(docker system df --format "{{json .}}" | jq "select(.Type==\"Local Volumes\")")

total=$(echo "$DF_OUTPUT" | jq -r ".TotalCount")
active=$(echo "$DF_OUTPUT" | jq -r ".Active")
reclaimable=0

if [[ $total -gt $active ]]; then
    # numfmt does not want the 'B' in input, we remove it using jq, after
    # splitting.
    reclaimable=$(echo "$DF_OUTPUT" | jq -r '.Reclaimable | split(" ")[0][0:-1]' | sed 's/k/K/' | numfmt --from=si)
fi

if [ "$reclaimable" -gt $WARN ]; then
    echo "WARNING : $(numfmt --to=si "$reclaimable") reclaimable volumes."
    exit 1
else
    echo "OK :  $(numfmt --to=si "$reclaimable") reclaimable volumes."
    exit 0
fi
