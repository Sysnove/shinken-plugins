#!/bin/bash

# This plugin calls the official `check_load` plugin but also checks if
# load1 is less than load15 thresholds, meaning that the load is recovering
# and we do not want CRITICAL or WARNING return codes.

if [ -x /usr/lib/nagios/plugins/check_load ] ; then
    out=$(/usr/lib/nagios/plugins/check_load $@)
    ret=$?
elif [ -x /usr/lib64/nagios/plugins/check_load ] ; then
    out=$(/usr/lib64/nagios/plugins/check_load $@)
    ret=$?
else
    exit "Could not find check_load executable."
    exit 3
fi


#OK - Charge moyenne: 0.49, 1.56, 1.84|load1=0.490;5.000;20.000;0; load5=1.560;5.000;15.000;0; load15=1.840;5.000;10.000┌(19:04:04)─(~)


if [ $ret -eq 0 -o $ret -eq 3 ] ; then
    echo $out
    exit $ret
else
    l1=$(echo $out | cut -d '|' -f 2 | cut -d ' ' -f 1 | cut -d '=' -f 2 | cut -d ';' -f 1)
    l1_warn=$(echo $out | cut -d '|' -f 2 | cut -d ' ' -f 1 | cut -d '=' -f 2 | cut -d ';' -f 2)
    l1_crit=$(echo $out | cut -d '|' -f 2 | cut -d ' ' -f 1 | cut -d '=' -f 2 | cut -d ';' -f 3)
    l5=$(echo $out | cut -d '|' -f 2 | cut -d ' ' -f 2 | cut -d '=' -f 2 | cut -d ';' -f 1)
    l5_warn=$(echo $out | cut -d '|' -f 2 | cut -d ' ' -f 2 | cut -d '=' -f 2 | cut -d ';' -f 2)
    l5_crit=$(echo $out | cut -d '|' -f 2 | cut -d ' ' -f 2 | cut -d '=' -f 2 | cut -d ';' -f 3)
    l15=$(echo $out | cut -d '|' -f 2 | cut -d ' ' -f 3 | cut -d '=' -f 2 | cut -d ';' -f 1)
    l15_warn=$(echo $out | cut -d '|' -f 2 | cut -d ' ' -f 3 | cut -d '=' -f 2 | cut -d ';' -f 2)
    l15_crit=$(echo $out | cut -d '|' -f 2 | cut -d ' ' -f 3 | cut -d '=' -f 2 | cut -d ';' -f 3)

    if (( $(echo "$l1 < $l15_warn" | bc -l) )) ; then
        echo $out | sed 's/WARNING/OK/g' | sed 's/CRITICAL/OK/g'
        exit 0
    elif (( $(echo "$l1 < $l15_crit" | bc -l) )) ; then
        echo $out | sed 's/CRITICAL/WARNING/g'
        exit 1
    else
        echo $out
        exit $ret
    fi
fi
