#!/bin/bash
#
# Description :
#
# This plugin checks the power consumption on Linux using Intel RAPL interface.
#
# CopyLeft 2022 Guillaume Subiron <guillaume@sysnove.fr>
#
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more details.
#

RET_OK=0
#RET_WARNING=1
#RET_CRITICAL=2
RET_UNKNOWN=3

if ! [ -e /sys/class/powercap/intel-rapl:0 ]; then
    echo "This host does not have RAPL domains. Cannot mesure power usage."
    exit $RET_UNKNOWN
fi

LAST_RUN_FILE=/var/tmp/nagios/check_rapl_power_last_run

NAGIOS_USER=${SUDO_USER:-$(whoami)}
if ! [ -d "$(dirname "$LAST_RUN_FILE")" ]; then
    install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$LAST_RUN_FILE")"
fi

if [ -f "$LAST_RUN_FILE" ] && [ ! -O "$LAST_RUN_FILE" ]; then
    echo "UNKNOWN: $LAST_RUN_FILE is not owned by $USER"
    exit $RET_UNKNOWN
fi

# If no last_run_file or if last_run_file is over 30 min old, we reset the check
if [ -z "$(find $LAST_RUN_FILE -mmin -30 -print)" ]; then
    for package in /sys/class/powercap/intel-rapl:?; do
        i=${package: -1}
        echo "last_energy_uj_$i=$(cat "$package/energy_uj")" >> $LAST_RUN_FILE
        #last_time_us[$i]=$(date +%s%6N)
        #last_energy_uj[$i]=$(cat "$package/energy_uj")
    done
    echo "$LAST_RUN_FILE did not exist or was too old, please run the check again."
    exit $RET_UNKNOWN
fi

# shellcheck disable=SC1090
source $LAST_RUN_FILE

last_run_time_us=$(date -r $LAST_RUN_FILE +%s%6N)
time_us=$(date +%s%6N)
delta_us=$((time_us - last_run_time_us))

total_delta_uj=0

truncate -s 0 $LAST_RUN_FILE

for package in /sys/class/powercap/intel-rapl:?; do
    i=${package: -1}

    energy_uj=$(cat "$package/energy_uj")
    echo "last_energy_uj_$i=$energy_uj" >> $LAST_RUN_FILE
    last_energy_uj_varname="last_energy_uj_$i"
    last_energy_uj=${last_energy_uj_varname}

    delta_uj=$((energy_uj - last_energy_uj))

    if [ "$delta_uj" -lt 0 ]; then
        max_energy_range_uj=$(cat "$package/max_energy_range_uj")
        delta_uj=$((delta_uj + max_energy_range_uj))
    fi

    total_delta_uj=$((total_delta_uj + delta_uj))
done

total_watt=$(echo "$total_delta_uj / $delta_us" | bc)
total_delta_j=$(echo "$total_delta_uj / 1000000" | bc)
delta_s=$(echo "$delta_us / 1000000" | bc)


echo "OK - Average power consumption ${total_watt}W (${total_delta_j}J over ${delta_s}s) | power=${total_watt}watt;;;0;;"
exit $RET_OK
