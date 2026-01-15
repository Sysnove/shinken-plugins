#!/bin/bash

# Checks that this host is in proper ansible groups

# magento_servers
if magento_vhosts=$(grep -Rl '/static.php?resource=' /etc/nginx/sites-enabled); then
    if ! jq -r '.host.ansible_groups[]' /etc/sysnove.json | grep -qw magento_servers; then
        echo "$magento_vhosts"
        echo "WARNING: This host should be in magento_servers."
        exit 1
    fi
fi

# mariadb_servers_big on servers with more than 15Go RAM
# if we configure mysql.
if [ -f /etc/mysql/conf.d/sysnove.cnf ]; then
#if jq -r '.host.ansible_groups[]' /etc/sysnove.json | grep -qw 'mysql_servers_generic'; then
    mem=$(grep MemTotal: /proc/meminfo | awk '{print int($2/1000000)}')
    if [ "$mem" -ge 15 ]; then
        if ! jq -r '.host.ansible_groups[]' /etc/sysnove.json | grep -E '^(mariadb|mysql)_servers_big'; then
            echo "WARNING: This host with ${mem}GB should be in mysql or mariadb_servers_big."
            exit 1
        fi
    fi
fi
