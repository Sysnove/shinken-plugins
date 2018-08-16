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
    if [ "$(curl -sL -w "%{http_code}\\n" http://infra-mon03.hostsvpn.sysnove.net:7770 -o /dev/null)" = "200" ]; then
        echo "CRITICAL - Arbiter process is UP but API does not answer"
    fi

    if [ "$(curl -sL -w "%{http_code}\\n" http://infra-mon03.hostsvpn.sysnove.net:7771 -o /dev/null)" = "200" ]; then
        echo "CRITICAL - Poller process is UP but API does not answer"
    fi

    if [ "$(curl -sL -w "%{http_code}\\n" http://infra-mon03.hostsvpn.sysnove.net:7772 -o /dev/null)" = "200" ]; then
        echo "CRITICAL - Broker process is UP but API does not answer"
    fi

    if [ "$(curl -sL -w "%{http_code}\\n" http://infra-mon03.hostsvpn.sysnove.net:7773 -o /dev/null)" = "200" ]; then
        echo "CRITICAL - Receiver process is UP but API does not answer"
    fi

    if [ "$(curl -sL -w "%{http_code}\\n" http://infra-mon03.hostsvpn.sysnove.net:7769 -o /dev/null)" = "200" ]; then
        echo "CRITICAL - Reactionner process is UP but API does not answer"
    fi

    if [ "$(curl -sL -w "%{http_code}\\n" http://infra-mon03.hostsvpn.sysnove.net:7768 -o /dev/null)" = "200" ]; then
        echo "CRITICAL - Scheduler process is UP but API does not answer"
    fi



    if ! test $(find /var/log/shinken/shinken-test.log -mmin -15); then
        echo "CRITICAL - Shinken log has not been updated in the last 15 minutes."
        exit $STATE_CRITICAL
    fi

    echo "OK - All daemons are running."
    exit $STATE_OK
fi

