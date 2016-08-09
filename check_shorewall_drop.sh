#!/bin/bash

if [ ! -e '/sbin/shorewall' ] ; then
    echo "UNKNOWN - shorewall command not found"
    exit 3
fi

dropped=$(shorewall show dynamic | grep DROP | wc -l)

echo "OK - $dropped IP address(es) currently dropped by Shorewall | dropped=$dropped"

# Always return OK
exit 0
