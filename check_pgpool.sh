#!/bin/bash

node_info="$(/usr/sbin/pcp_node_info -h localhost -U pgpool --no-password)"
node_info_ret=$?

if [ $node_info_ret != 0 ]; then
    echo "UNKNOWN : pcp_node_info returned $node_info_ret"
    exit 3
fi

pool_status="$(/usr/sbin/pcp_pool_status -h localhost -U pgpool --no-password)"
pool_status_ret=$?

if [ $pool_status_ret != 0 ]; then
    echo "UNKNOWN : pcp_pool_status returned $node_info_ret"
    exit 3
fi

proc_info="$(/usr/sbin/pcp_proc_info -h localhost -U pgpool --no-password)"
proc_info_ret=$?

if [ $proc_info_ret != 0 ]; then
    echo "UNKNOWN : pcp_proc_info returned $node_info_ret"
    exit 3
fi

IFS=$'\n'

nominal_primary_id=0
node_id=0

criticals=()
warnings=()

for line in $node_info; do
    status=$(echo $line | cut -d ' ' -f 3)
    backend_role=$(echo $line | cut -d ' ' -f 7)
    backend_role_actual=$(echo $line | cut -d ' ' -f 8)
    replication_delay=$(echo $line | cut -d ' ' -f 9)

    # Check for node status:
    #   0. Initializing
    #   1. Node is up, no connections
    #   2. Node is up, connections are pooled
    #   3. Node is down
    if [ $status -eq 3 ] ; then
        # Nominal primary is down
        if [ $node_id -eq $nominal_node_id ] ; then
            criticals+=("PGPool CRITICAL : Nominal primary node $node_id is down")
        elif [ $backend_role_actual == "primary" ]; then
            criticals+=("PGPool CRITICAL : Primary node $node_id is down")
        else
            warnings+=("PGPool WARNING : Secondary node $node_id is down")
        fi
    else
        if [ $backend_role_actual == "primary" ]; then
            if [ $nominal_primary_id != $node_id ]; then
                criticals+=("PGPool WARNING : Node $node_id is primary instead of $nominal_primary_id)")
            fi
        fi

        if [ $replication_delay -gt 10 ]; then
            warnings+=("PGPool WARNING : Node $node_id lag is $replication_delay")
        fi
    fi

    if [ "$backend_role" != "$backend_role_actual" ] ; then
        warnings+=("PGPool WARNING : Real backend role for $node_id is not consistent")
    fi

    node_id=$((nodeid+1))
done

nb_primaries=$(echo $node_info | grep "primary" | wc -l)
if [ $nb_primaries -eq 0 ]; then
    criticals+=("PGPool CRITICAL : No primary found in the cluster.")
    exit 2
elif [ $nb_primaries -gt 1 ]; then
    warnings+=("PGPool WARNING : No primary found in the cluster.")
fi



max_pool=$(echo "$pool_status" | grep 'name : max_pool' -A 1 | grep '^value:' | cut -d ' ' -f 2)
num_init_children=$(echo "$pool_status" | grep 'name : num_init_children' -A 1 | grep '^value:' | cut -d ' ' -f 2)
nb_connections=$(echo "$proc_info" | grep -v 'Wait for connection' | wc -l)

max_connections=$((max_pool*num_init_children))
warn_connections=$((max_connections*75/100))
crit_connections=$((max_connections*90/100))

if [ $nb_connections -gt $crit_connections ]; then
    criticals+=("PGPool CRITICAL : $nb_connections connections on $max_connections (>90%)")
elif [ $nb_connections -gt $warn_connections ]; then
    warnings+=("PGPool CRITICAL : $nb_connections connections on $max_connections (>75%)")
fi



if [ ${#criticals[@]} -gt 0 ] ; then
    printf '%s\n' "${criticals[@]}"
    exit 2
fi

if [ ${#warnings[@]} -gt 0 ] ; then
    printf '%s\n' "${warnings[@]}"
    exit 1
fi

echo "PGPool OK : $nb_connections connections on $max_connections | connections=$nb_connections;$warn_connections;$crit_connections;0;$max_connections"
exit 0
