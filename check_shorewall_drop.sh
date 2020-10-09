#!/bin/bash


if which ipset > /dev/null 2>&1; then
    dropped=$(ipset list SW_DBL4 | grep 'Number of entries:' | awk '{print $4}')

    if [ -z "$dropped" ]; then
        echo "UNKNOWN - Could not find entries in ipset list SW_DBL4"

        # Always return OK
        exit 3
    fi
else
    # Without ipset, use shorewall show dynamic
    if ! which shorewall > /dev/null 2>&1 ; then
        echo "UNKNOWN - shorewall command not found"
        exit 3
    fi

    dropped=$(shorewall show dynamic | grep DROP | wc -l)
fi

echo "OK - $dropped IP address(es) currently dropped by Shorewall | dropped=$dropped"

# Always return OK
exit 0
