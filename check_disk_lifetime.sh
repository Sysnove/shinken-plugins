#!/bin/bash

DISK=$1

E_OK=0
E_WARNING=1
#E_CRITICAL=2
E_UNKNOWN=3

if ! [ -e "$DISK" ]; then
    echo "UNKNOWN - $DISK not found"
    exit $E_UNKNOWN
fi

if grep -q 1 /sys/block/"$(basename "$DISK")"/queue/rotational; then
    echo "OK - $DISK is rotational"
    exit $E_OK
fi

if [[ "$DISK" =~ sd ]]; then
    nvme=false
elif [[ "$DISK" =~ nvme ]]; then
    nvme=true
else
    echo "UNKOWN - $DISK is not sd nor nvme"
    exit $E_UNKNOWN
fi

if ! [[ "$(hostname)" =~ ^infra ]]; then
    echo "OK - For now this host is not managed by this check"
    exit $E_OK
fi


LAST_RUN_FILE=/var/tmp/nagios/check_disk_lifetime_last_run_$(basename "$DISK")

NAGIOS_USER=${SUDO_USER:-$(whoami)}
if ! [ -d "$(dirname "$LAST_RUN_FILE")" ]; then
    install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$LAST_RUN_FILE")"
fi

if [ -f "$LAST_RUN_FILE" ] && [ ! -O "$LAST_RUN_FILE" ]; then
    echo "UNKNOWN: $LAST_RUN_FILE is not owned by $USER"
    exit $E_UNKNOWN
fi

last_change=-1
last_value=101
last_status=
last_output=""

now=$(date +%s)

if ! smartctl=$(sudo /usr/sbin/smartctl -a "$DISK"); then
    echo "UNKNOWN - smartctl: $smartctl"
    exit $E_UNKNOWN
fi

if $nvme; then
    used=$(echo "$smartctl" | grep "Percentage Used:" | awk '{print $3}' | sed 's/%$//g')
    remain=$((100 - used))
    data_units_written=$(echo "$smartctl" | grep "Data Units Written:" | cut -d '[' -f 1 | grep -Eo '[0-9].*' | sed 's/[^0-9]//g')
else
    remain=$(echo "$smartctl" | grep Percent_Lifetime_Remain | awk '{print $4}' | sed 's/^0*//g')
    data_units_written=$(echo "$smartctl" | grep Total_LBAs_Written | awk '{print $10}' | sed 's/^0*//g')
fi

if [ -z "$remain" ] || [ -z "$data_units_written" ]; then
    echo "UNKNOWN - could not find remain or data_units_written in smartctl $DISK"
    exit $E_UNKNOWN
fi

# shellcheck disable=SC1090
source "$LAST_RUN_FILE"

perfdata="remain=$remain%; total_sector_written=$data_units_written;"

# If no change, print the same output and exit the same way
if [ "$remain" -eq "$last_value" ]; then
    echo "$last_output | $perfdata"
    exit "$last_status"
fi

period=$((now - last_change))

# If the previous change was more than one week ago, it's OK
if [ $last_change -eq -1 ] || [ $period -gt 604800 ] ; then
    status=$E_OK
    output="OK - $DISK lifetime is ${remain}% remaining and has not change since $(date -d @"$now" +'%Y-%m-%d %H:%M:%S')"
else # We have lost 1% in less than one week
    status=$E_WARNING
    output="WARNING - $DISK has lost $((last_status - remain))% lifetime in ${period}s (${remain} remaining)"
fi

echo "
last_change=$now
last_value=$remain
last_status=$status
last_output=\"$output\"
" > "$LAST_RUN_FILE"

echo "$output | $perfdata"
exit "$status"
