#!/bin/bash

maldetsessions=/usr/local/maldetect/sess

if ! [ -e $maldetsessions ] ; then
    echo "UNKNOWN: Maldet is not installed"
    exit 3
fi

last=$maldetsessions/session.$(<$maldetsessions/session.last)

if ! [ -e "$last" ] ; then
    echo "UNKNOWN: Maldet report not found"
    exit 3
fi

hits=$(grep "TOTAL HITS:" "$last" | grep -o '[[:digit:]]\+' | paste -sd+ | bc)

if [ "$hits" -eq 0 ] ; then
    echo "OK: No malware found."
    exit 0
fi

if [ "$hits" -gt 0 ] ; then
    echo "CRITICAL: $hits malwares found !"
    exit 2
fi

echo "UNKNOWN: total hits = $hits"
exit 3
