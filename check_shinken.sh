#!/bin/sh

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

daemons="scheduler poller reactionner broker receiver arbiter"
down=""

for daemon in $daemons ; do
    ps ax | grep -v "grep" | grep -q "shinken-$daemon" || down="$down $daemon"
done

if [ "$down" != "" ] ; then
    echo "CRITICAL - Daemons down:$down"
    exit $STATE_CRITICAL
else
    # :TODO:maethor:180816: Test ports




    if ! test $(find /var/log/shinken/shinken-test.log -mmin -15); then
        echo "CRITICAL - Shinken log has not been updated in the last 15 minutes."
        exit $STATE_CRITICAL
    fi

    echo "OK - All daemons are running."
    exit $STATE_OK
fi

