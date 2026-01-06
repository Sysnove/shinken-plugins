#!/bin/bash


if which ipset > /dev/null 2>&1; then
    dropped=$(ipset list SW_DBL4 | grep 'Number of entries:' | awk '{print $4}')

    if [ -z "$dropped" ]; then
        # Yep… I known, I don't care
        dropped=0
    fi

    # Check if there is no full ipset
    ipsets=$(ipset -L | grep Name | cut -d ' ' -f 2)

    for setname in $ipsets; do
        if size=$(ipset list "$setname" | grep '^Number of entries' | awk '{print $NF}' 2>/dev/null); then
            maxelem=$(ipset list "$setname" | grep '^Header' | sed -E 's/^.* maxelem ([0-9]+) .*$/\1/')

            if [[ "$size" -gt "$((maxelem - 1000))" ]] ; then
                echo "WARNING - ipset $setname is full | dropped=$dropped"
                exit 1
            fi
        fi
    done
else
    # Without ipset, use shorewall show dynamic
    if ! which shorewall > /dev/null 2>&1 ; then
        echo "UNKNOWN - shorewall command not found"
        exit 3
    fi

    dropped=$(shorewall show dynamic | grep -c DROP)
fi

echo "OK - $dropped IP addresses currently dropped by Shorewall | dropped=$dropped"
exit 0
