#!/bin/sh

if [ -d /usr/lib/nagios/plugins ]; then
    NAGIOS_PLUGINS=/usr/lib/nagios/plugins
else
    NAGIOS_PLUGINS=/usr/lib64/nagios/plugins
fi

set -e

if timeout 5s sudo /usr/sbin/ipmi-sensors > /dev/null 2>&1; then
    cpu_min_freq="$(LC_ALL=C lscpu | grep "min MHz" | awk '{printf "%.0f\n", $NF + 20}')"
    [ -z "$cpu_min_freq" ] && cpu_min_freq=820
    if [ "$(grep 'cpu MHz' /proc/cpuinfo | awk '{sum+=$NF; nb+=1} END {printf "%.0f\n", sum/nb}')" -lt "$cpu_min_freq" ]; then
        #echo "CRITICAL - CPU is running at 800Mhz. Could be an hardware problem. Please check impi-sensors."
        #exit 2
        timeout 5s $NAGIOS_PLUGINS/check_ipmi_sensor --nosel -xT Entity_Presence,Voltage,Physical_Security,Management_Subsystem_Health | cut -d '|' -f 1
    fi
fi
