#!/bin/bash

maldetsessions=/usr/local/maldetect/sess

DURATION_WARN="$1"

if ! [ -e $maldetsessions ] ; then
    echo "UNKNOWN: Maldet is not installed"
    exit 3
fi

last=$maldetsessions/session.$(<$maldetsessions/session.last)

if ! [ -e "$last" ] ; then
    echo "UNKNOWN: Maldet report not found"
    exit 3
fi

files=$(grep "TOTAL FILES:" "$last" | grep -o '[[:digit:]]\+' | paste -sd+ | bc)
hits=$(grep "TOTAL HITS:" "$last" | grep -o '[[:digit:]]\+' | paste -sd+ | bc)
duration=$(grep "ELAPSED:" "$last" | awk '{print $2}' | sed 's/s//')
perfdata="duration=${duration}s;$DURATION_WARN;;0; files=${files}; hits=${hits};"

if [ "$hits" -lt 0 ] ; then
    echo "UNKNOWN: total hits = $hits"
    exit 3
fi

if [ "$hits" -gt 0 ] ; then
    echo "CRITICAL: $hits malwares found ! | $perfdata" 
    exit 2
fi

if [ -n "$DURATION_WARN" ] && [ "$duration" -ge "$DURATION_WARN" ]; then
    echo "Warning: No malware found but last scan took ${duration} seconds. | $perfdata"
    exit 1
fi

if [ "$hits" -eq 0 ] ; then
    echo "OK: No malware found, last scan took ${duration} seconds. | $perfdata"
    exit 0
fi


