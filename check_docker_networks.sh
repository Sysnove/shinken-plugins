#!/bin/bash
# Based upon https://github.com/docker-archive/ip-util-check

export DOCKER_CERT_PATH
export DOCKER_HOST
export DOCKER_TLS_VERIFY

set -e

# Per-network state keyed on network ID
#
declare -A NET2SUB	  # list of subnets for each overlay network
declare -A NET2CAP	  # network capacity of each overlay network
declare -A NET2NAME	  # network name of each overlay network
declare -A NET2NCIP	  # number of container IP addresses for each overlay network
declare -A NET2NVIP	  # number of virtual IP addresses for each overlay network
declare -A NET2NNODES # number of nodes where the overlay is currently used


# Gather node, overlay network and service IDs
#echo "Gathering basic cluster state"
NODEIDS=$(docker node ls -q)
NETS=$(docker network ls --filter driver=overlay | awk 'NR != 1 && $2 != "ingress" {print $1}')
SVCIDS=$(docker service ls -q)


#echo "Gathering overlay network information" | ts
for net in $NETS ; do
    networkInspect=$( docker network inspect -v "$net" )
    NET2NAME[$net]=$(echo "$networkInspect" | jq -r '.[].Name')
    set +e
    NET2SUB[$net]=$(echo "$networkInspect" | jq -r '.[].IPAM.Config[].Subnet' 2>/dev/null)
    if [ -z "${NET2SUB[$net]}" ] ; then
        NET2SUB[$net]=$(docker network inspect "${NET2NAME[$net]}" | jq -r '.[].IPAM.Config[].Subnet' 2>/dev/null)
    fi
    set -e
    NET2CAP[$net]=0
    NET2NCIP[$net]=0
    NET2NVIP[$net]=0
    NET2NNODES[$net]=$(echo "$networkInspect" | jq -r '.[].Peers | length')
    for sub in ${NET2SUB[$net]} ; do
        pfxlen=$(echo "$sub" | awk -F / '{print $2}')
        subcap=$(( (1 << (32 - pfxlen)) - 3 ))
        NET2CAP[$net]=$(( ${NET2CAP[$net]} + subcap ))
    done

    NET2NVIP[$net]="$(echo "$networkInspect" | jq "[.[].Services[]?.VIP] | length")"
    NET2NCIP[$net]="$(echo "$networkInspect" | jq "[.[].Services[]?.Tasks[]?.EndpointIP] | length")"
done

#echo "Overlay IP Utilization Report" | ts
for net in $NETS ; do
	if [ "${NET2CAP[$net]}" -gt 0 ] ; then
		USE=$(( ${NET2NCIP[$net]} + ${NET2NVIP[$net]} ))
		SAFECAP=$(( ${NET2CAP[$net]} * 75 / 100 ))
		if [ $(( USE + ${NET2NNODES[$net]} )) -ge $SAFECAP ] ; then
            echo "CRITICAL : Docker network \"${NET2NAME[$net]}\" is using $USE IP addresses over ${NET2CAP[$net]}"
            exit 2
		fi
	fi
done


# Check if a docker network conflicts with local networks
for subnet in $(docker network inspect $(docker network ls -q) | jq -r '.[] | select(.IPAM.Config != null) | .IPAM.Config[].Subnet'); do
    ip="$(echo "$subnet" | cut -d '/' -f 1)"
    if ip route get "$ip" | grep "$ip" | grep -v docker | grep -v 'br-' | grep -q broadcast; then
        iface=$(ip route get $ip | grep $ip | grep broadcast | cut -d ' ' -f 4)
        name=$(docker network inspect $(docker network ls -q) | jq -r '.[] | select(.IPAM.Config != null) | .Name, .IPAM.Config[].Subnet' | grep "$subnet" -B 1 | head -n 1)
        echo "WARNING : Docker network $name uses same subnet than iface $iface ($subnet)"
        exit 1
    fi
done

echo "OK : All docker networks are fine."
