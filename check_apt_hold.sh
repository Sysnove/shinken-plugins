#!/bin/bash

nb_updates=0
nb_security_updates=0

for pkg in $(sudo apt-mark showhold); do
    policy="$(apt-cache policy $pkg)"
    installed=$(echo "$policy" | head -n 2 | tail -n 1 | cut -d ':' -f 2)
    candidate=$(echo "$policy" | head -n 3 | tail -n 1 | cut -d ':' -f 2)
    if [[ "$installed" != "$candidate" ]]; then
        nb_updates=$((nb_updates + 1))
        if echo "$policy" | fgrep -B 20 '***' | grep Packages | grep -q security; then
            nb_security_updates=$((nb_updates + 1))
        fi
    fi
done

if [[ $nb_security_updates -gt 0 ]]; then
    echo "CRITICAL: $nb_updates holded packages available for upgrade ($nb_security_updates security)."
    exit 2
fi

if [[ $nb_updates -gt 0 ]]; then
    echo "WARNING: $nb_updates holded packages available for upgrade."
    exit 1
fi

echo "OK: Holded packages are up to date."
exit 0
