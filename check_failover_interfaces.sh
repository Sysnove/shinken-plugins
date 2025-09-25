#!/bin/sh

for failover in $(grep 'ip addr add' /etc/network/interfaces.d/failovers.cfg | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'); do
    interface=$(grep 'ip addr add' /etc/network/interfaces.d/failovers.cfg | grep -oE 'dev [^ ]+' | awk '{print $NF}' | head -n 1)

    if ! grep -qR "^iface $interface inet" /etc/network/interfaces.d /etc/network/interfaces; then
        echo "CRITICAL - Failover $failover is configured in /e/n/i.d/failovers.cfg but interface $interface is not configured in /e/n/interfaces. IP will not mount on systemd-networkd restart."
     exit 2
    fi
done

echo "OK - Failovers interfaces are well configured."
exit 0
