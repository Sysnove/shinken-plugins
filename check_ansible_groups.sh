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
