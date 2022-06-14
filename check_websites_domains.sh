#!/bin/bash

#if [ -d "/usr/local/ispconfig" ]; then
#    echo "This script is disabled on ISPConfig servers."
#    exit 0
#fi

if [ -d "/etc/nginx/sites-enabled" ]; then
    websites=$(grep -hRE '^[^#]*[^\$#]server_name' /etc/nginx/sites-enabled | grep -v '_;' | sed 's/;//g' | sed 's/server_name//g' | sed 's/\*/wildcard/g' | xargs -n 1 | sort | uniq)
    #server="Nginx"
fi

if [ -d "/etc/apache2/sites-enabled" ]; then
    # COMMENT I think we don't need to check ServerAlias because we follow redirections
    websites=$(grep -hRE '^[^#]*[^\$#]ServerName' /etc/apache2/sites-enabled/ | sed 's/ServerName//g' | sed 's/\*/wildcard/g' | xargs -n 1 | sort | uniq)
    #server="Apache2"
fi

for website in $websites; do
    ./check_domain.sh -C /var/tmp/nagios/check_domain -a 30 -d "$website"
done
