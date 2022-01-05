#!/bin/bash

nb_on_hold=0
nb_updates=0
updates=""
nb_security_updates=0
security_updates=""

for pkg in $(apt-mark showhold); do
    nb_on_hold=$((nb_on_hold + 1))
    policy=$(apt-cache policy "$pkg")
    installed=$(echo "$policy" | head -n 2 | tail -n 1 | awk '{print $2}')
    candidate=$(echo "$policy" | head -n 3 | tail -n 1 | awk '{print $2}')
    if [[ "$installed" != "$candidate" ]]; then
        updates="$updates $pkg"
        nb_updates=$((nb_updates + 1))
        if echo "$policy" | grep -F -B 20 '***' | grep Packages | grep -q security; then
            security_updates="$security_updates $pkg"
            nb_security_updates=$((nb_security_updates + 1))
        fi
    fi
done

if [[ $nb_security_updates -gt 0 ]]; then
    echo "CRITICAL: $nb_security_updates packages on hold need a security update : $(echo "$security_updates" | xargs)"
    exit 2
fi

if [[ $nb_updates -gt 0 ]]; then
    echo "OK but $nb_updates/$nb_on_hold packages on hold are available for upgrade : $(echo "$updates" | xargs)"
    exit 0
fi

if [[ $nb_on_hold -gt 0 ]]; then
    echo "OK: $nb_on_hold packages on hold are up to date."
    exit 0
fi

echo "OK: No package on hold."
exit 0
