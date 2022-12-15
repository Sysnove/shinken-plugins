#!/bin/bash

if ! systemctl is-active --quiet energizta; then
    echo "UNKNOWN : energizta.sh is not running"
    exit 3
fi

last_line=$(tail -n 1 /var/lib/energizta/energizta.log | grep '^{"')

if [ -z "$last_line" ]; then
    echo "UNKNOWN : Fail to get json from /var/lib/energizta/energizta.log"
    exit 3
fi

if ! echo "$last_line" | jq > /dev/null; then
    echo "UNKNOWN : failed to parse last line from /var/lib/energizta/energizta.log"
    exit 3
fi

timestamp=$(echo "$last_line" | jq '.timestamp')

freshness=$(( $(date +%s) - timestamp ))

if [ $freshness -gt 600 ]; then
    echo "UNKNOWN : last energizta.sh line was $freshness seconds ago"
    exit 3
fi

IFS=","

perfdata=""
power="?"
rapl="?"

for var in $(echo "$last_line" | jq -c '.powers' | sed 's/}//g'); do
    name=$(echo "$var" | cut -d '"' -f 2)
    value=$(echo "$var" | cut -d ':' -f 2)
    perfdata="$perfdata ${name}=${value}W"

    if [ "$name" == "rapl_total_watt" ]; then
        rapl=$value
    fi

    if [ "$name" == "dcmi_cur_watt" ] || [[ "$name" == ipmi_* ]]; then
        power=$value
    fi

    if [ "$name" == "sensors_acpi_watt" ]; then
        if [ "$power" == "?" ]; then
            power=$value
        fi
    fi
done

if [ "$power" != "?" ] && [ "$rapl" != "?" ]; then
    ratio=$(( (rapl * 100) / power ))
    perfdata="$perfdata rapl_ratio=$ratio%;;;0;100"
fi

echo "OK - Power consumption ${power}W (RAPL ${rapl}W) | $perfdata"
