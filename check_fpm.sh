#!/bin/zsh

perfdata=""

nb_pools=0
nb_pools_down=0
pools_down=""
nb_pools_unknown=0
pool_unknown=""

ret=0

for sock in $(cat /etc/php*/**/fpm/pool.d/*.conf | grep '^listen =' | cut -d '=' -f 2) ; do
    config_file=$(grep -l "listen = $sock" /etc/php*/**/fpm/pool.d/*.conf)
    php_version=$(echo $config_file | cut -d '/' -f 4)
    pool_name=${$(basename $config_file)%.*}
    pool_fullname=php${php_version}-fpm/${pool_name}

    # ISPConfig
    if [[ $pool_name = 'ispconfig' || $pool_name = 'apps' ]] ; then
        continue;
    fi

    nb_pools=$((nb_pools+1))

    output=$(SCRIPT_NAME=/status SCRIPT_FILENAME=/status REQUEST_METHOD=GET timeout 5s cgi-fcgi -bind -connect $sock 2> /dev/null)

    if [ $? -ne 0 ] ; then
        nb_pools_down=$(($nb_pools_down + 1))
        if pgrep 'php-fpm.*'"$php_version" -a | grep -q "$pool_name"'[ ]*'; then
            pools_down="$pools_down$pool_fullname (max_children_reached), "
        else
            pools_down="$pools_down$pool_fullname, "
        fi
    fi

    if echo $output | grep -q "File not found"; then
        output=$(SCRIPT_NAME=/fpm_status SCRIPT_FILENAME=/fpm_status REQUEST_METHOD=GET timeout 5s cgi-fcgi -bind -connect $sock 2> /dev/null)
    fi

    out_pool_name=$(echo "$output" | grep '^pool:' | awk '{print $2}')
    out_pool_listen_queue=$(echo "$output" | grep '^listen queue:' | awk '{print $3}')
    out_pool_idle_processes=$(echo "$output" | grep '^idle processes:' | awk '{print $3}')
    out_pool_active_processes=$(echo "$output" | grep '^active processes:' | awk '{print $3}')
    #pool_max_children_reached=$(echo "$output" | grep '^max children reached:' | awk '{print $4}')

    if [ -z "$out_pool_name" ]; then
        nb_pools_unknown=$(($nb_pools_unknown + 1))
        pool_unknown="$pool_unknown$pool_fullname, "
    fi

    # ISPConfig
    if ! [[ $out_pool_name == 'web'* ]] ; then
        perfdata="$perfdata php${php_version//./}_${pool_name}_listen_queue=${out_pool_listen_queue:-0} php${php_version//./}_${pool_name}_idle_procs=${out_pool_idle_processes:-0} php${php_version//./}_${pool_name}_active_procs=${out_pool_active_processes:-0}"
    fi
done

if [ $nb_pools -eq 0 ] ; then
    echo "UNKNOWN - 0 FPM pool found, please check your configuration."
    exit 3
fi

if [ $nb_pools_down -gt 0 ] ; then
    echo "CRITICAL - $nb_pools_down/$nb_pools pools are down or overloaded (${pools_down:0:-2}) | $perfdata"
    exit 2
fi

if [ $nb_pools_unknown -gt 0 ] ; then
    echo "UNKNOWN - $nb_pools_unknown/$nb_pools pools are unknown (${pool_unknown:0:-2}) | $perfdata"
    exit 3
fi

echo "OK - $nb_pools PHP-FPM pools found | $perfdata"

exit $ret
