#!/bin/bash

archives=$(jq -r '.archives[] | .archive' /var/backups/borglist.json)

keephourly=$(grep keephourly /etc/backup.d/91_all.borg | cut -d ' ' -f 3)
keepdaily=$(grep keepdaily /etc/backup.d/91_all.borg | cut -d ' ' -f 3)
keepmonthly=$(grep keepmonthly /etc/backup.d/91_all.borg | cut -d ' ' -f 3)

missing=()

for i in $(seq "$((keepmonthly - 1))" -1 1); do
    archive=$(date -d "$i months ago" '+%Y-%m')
    if ! echo "$archives" | grep -Eq "^$archive"; then
        missing+=("$archive")
    fi
done
for i in $(seq "$((keepdaily - 1))" -1 1); do
    archive=$(date -d "$i day ago" '+%Y-%m-%d')
    if ! echo "$archives" | grep -Eq "^$archive"; then
        missing+=("$archive")
    fi
done
if [ "$keephourly" -gt 1 ]; then
    for i in $(seq "$keephourly" -1 1); do
        archive=$(date -d "$i hour ago" '+%Y-%m-%d-%H')
        if ! echo "$archives" | grep -Eq "^$archive"; then
            missing+=("$archive")
        fi
    done
fi

if [ ${#missing[@]} -gt 1 ]; then
    echo "CRITICAL - Missing ${#missing[@]} archives : " "${missing[@]}"
    exit 2
elif [ ${#missing[@]} -gt 0 ]; then
    echo "OK - But missing ${#missing[@]} archives : " "${missing[@]}"
    exit 0
else
    echo "OK - Found all archives"
    exit 0
fi

