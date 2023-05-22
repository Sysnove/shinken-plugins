#!/bin/bash

E_OK=0
E_UNKNOWN=3

WARNINGS=()
IGNORED=()
LAST_WARNING=""
PERFDATA=""
REMAINS=()
RET=$E_OK

if ! [[ "$(hostname)" =~ ^(infra|clibre|mt|cz|okina|algo) ]]; then
    echo "OK - For now this host is not managed by this check"
    exit $E_OK
fi

# shellcheck disable=SC2010
for DEVICE in $(ls /sys/block | grep -Ev '^(sr|vd|fd)'); do
    if [ -L "/sys/block/$DEVICE/device" ]; then

    if [[ "$DEVICE" =~ sd ]]; then
        true
    elif [[ "$DEVICE" =~ nvme ]]; then
        # /dev/nvme1n1 -> /dev/nvme1
        DEVICE=$(echo "$DEVICE" | grep -o '^[a-z/]*[0-9]')
    else
        echo "UNKOWN - $DEVICE is not sd nor nvme"
        exit $E_UNKNOWN
    fi

        DEVPATH=$(echo "/dev/$DEVICE" | sed 's#!#/#g')
        out=$(/usr/local/nagios/plugins/check_disk_lifetime.sh "$DEVPATH")
        ret=$?

        if [ $ret -eq 3 ]; then
            echo "$out"
            exit 3
        fi
        
        if echo "$out" | grep -q ' | ' ; then
            perfdata=$(echo "$out" | cut -d '|' -f 2 | sed "s#=#_$DEVPATH=#g")
            PERFDATA="$PERFDATA $perfdata"
            REMAINS+=("$DEVICE=$(echo "$perfdata" | grep -Eo '[0-9]+%')")
            
            if [ $ret -eq 1 ]; then
                RET=$ret
                WARNINGS+=("$DEVPATH")
                LAST_WARNING="$(echo "$out" | cut -d '|' -f 1)"
                echo "$LAST_WARNING"
            fi
        else
            echo "$out"
            IGNORED+=("$DEVPATH")
        fi
    fi
done

if [ ${#IGNORED[@]} -gt 0 ]; then
    IGNORED_STR=" (ignored: ${IGNORED[*]})"
fi

if [ ${#REMAINS[@]} -eq 0 ]; then
    echo "OK - No disk to check$IGNORED_STR"
elif [ $RET -eq 0 ]; then
    echo "OK - Disks lifetime are OK (${REMAINS[*]})$IGNORED_STR | $PERFDATA"
elif [ ${#WARNINGS[@]} -eq 1 ]; then
    echo "$LAST_WARNING | $PERFDATA"
else
    echo "WARNING : ${WARNINGS[*]} have lost more than 1% lifetime in less than 7 days (${REMAINS[*]})$IGNORED_STR | $PERFDATA"
fi

exit $RET
