#!/usr/bin/env python3

import ipaddress
import json
import subprocess
import sys

def main():
    # Retrieve local interfaces.
    ifaces = [{
        "name": iface.decode().split()[0],
        "address": ipaddress.ip_interface(iface.split()[2].decode())
    } for iface in subprocess.check_output(
        "ip -br -4 addr show scope global",
        shell=True
    ).splitlines()]

    # Retrieve Docker network list.
    network_ids = subprocess.check_output(
        "docker network ls --filter driver=overlay -q",
        shell=True
    ).decode("utf-8").splitlines()

    for network_id in network_ids:
        # Retrieve Docker network information.
        try:
            network = json.loads(
                subprocess.check_output(
                    f"docker network inspect -v {network_id}",
                    shell=True
                )
            )[0]
        except:
            pass

        # Sometimes command fails with -v.
        if not network:
            network = json.loads(
                subprocess.check_output(
                    f"docker network inspect {network_id}",
                    shell=True
                )
            )[0]

        name = network['Name']

        nvip = 0
        ncip = 0

        for service_name, service in network.get('Services', {}).items():
            nvip = nvip + 1
            ncip = ncip + len(service.get('Tasks', []))

        nnodes = len(network.get('Peers', []))

        capacity = 0

        for ipam_config in network['IPAM'].get('Config', []):
            subnet = ipaddress.ip_network(ipam_config['Subnet'])
            capacity = capacity + len(list(subnet.hosts()))

            for iface in ifaces:
                iface_name = iface['name']
                iface_address = iface['address']

                # Check network overlapping with local interaces.
                if subnet.overlaps(iface_address.network) and name != 'dummy':
                    print(f"WARNING : Docker network {name} overlaps iface {iface_name} ({iface_address.network})")
                    sys.exit(1)

        if capacity > 0:
            usage = nvip + ncip
            safe_capacity = capacity * 75 / 100

            if usage + nnodes >= safe_capacity:
                print(f'CRITICAL : Docker network "{name}" is using {usage} IP addresses over {capacity}')
                sys.exit(2)

    print('OK : All docker networks are fine.')


if __name__ == "__main__":
    main()
