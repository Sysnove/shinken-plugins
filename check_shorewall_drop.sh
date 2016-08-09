#!/bin/sh

dropped=$(sudo shorewall show dynamic | grep DROP | wc -l)

echo "OK - $dropped IP address(es) currently dropped by Shorewall | dropped=$dropped"

# Always return OK
return 0
