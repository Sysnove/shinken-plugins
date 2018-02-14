#!/bin/zsh

perfdata=""

nb_pools=0
nb_pools_down=0
sockets_down=""
nb_pools_unknown=0
pool_unknown=""
nb_pools_max_children_reached=0
pools_max_children_reached=""

ret=0

for sock in $(cat /etc/php*/**/fpm/pool.d/*.conf | grep '^listen =' | cut -d '=' -f 2) ; do
    if [[ $sock =~ .*\.sock ]]; then
        # It is a socket file
        socket_name=${$(basename $sock)%.*}
    else
        # It is an IP/Port
        config_file=$(grep -l "listen = $sock" /etc/php*/**/fpm/pool.d/*.conf)
        socket_name=${$(basename $config_file)%.*}
    fi

    nb_pools=$((nb_pools+1))

    output=$(SCRIPT_NAME=/fpm_status SCRIPT_FILENAME=/fpm_status REQUEST_METHOD=GET cgi-fcgi -bind -connect $sock)

    if [ $? -ne 0 ] ; then
        nb_pools_down=$(($nb_pools_down + 1))
        sockets_down="$sockets_down $socket_name "
    fi

    pool_name=$(echo "$output" | grep '^pool:' | awk '{print $2}')
    pool_listen_queue=$(echo "$output" | grep '^listen queue:' | awk '{print $3}')
    pool_idle_processes=$(echo "$output" | grep '^idle processes:' | awk '{print $3}')
    pool_active_processes=$(echo "$output" | grep '^active processes:' | awk '{print $3}')
    pool_max_children_reached=$(echo "$output" | grep '^max children reached:' | awk '{print $4}')

    if [ -z "$pool_name" ]; then
        nb_pools_unknown=$(($nb_pools_unknown + 1))
        pool_unknown="$pool_unknown $socket_name "
    fi

    perfdata="$perfdata ${socket_name}_listen_queue=${pool_listen_queue:-0} ${socket_name}_idle_procs=${pool_idle_processes:-0} ${socket_name}_active_procs=${pool_active_processes:-0}"

    if [[ $pool_max_children_reached > 0 ]] ; then
        nb_pools_max_children_reached=$(($nb_pools_max_children_reached + 1))
        pools_max_children_reached="$pools_max_children_reached $socket_name:$pool_max_children_reached "
    fi
done

if [ $nb_pools_down -gt 0 ] ; then
    echo "CRITICAL - $nb_pools_down/$nb_pools pools down ($sockets_down) | $perfdata"
    exit 2
fi

if [ $nb_pools_unknown -gt 0 ] ; then
    echo "UNKNOWN - $nb_pools_unknown/$nb_pools pools unknown ($pool_unknown) | $perfdata"
    exit 3
fi

if [ $nb_pools_max_children_reached -gt 0 ] ; then
    echo "WARNING - $nb_pools_max_children_reached/$nb_pools pools have reached max_children ($pools_max_children_reached) | $perfdata"
    exit 1
fi

echo "OK - $nb_pools PHP-FPM sockets found | $perfdata"

exit $ret
