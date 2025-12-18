#!/bin/bash

if [ -d '/etc/shorewall/rules.d' ]; then
    custom_confs="$(grep -REL '# Ansible managed:' /etc/shorewall/rules.d/ | grep -v 02_blacklist_ipinfo | grep -v 02_blacklist_custom | grep -Ev '90_.+_backups' | paste -sd ' ' -)"
fi

if [ -n "$custom_confs" ]; then
    echo "WARNING - These custom configs should be managed by Ansible : $custom_confs"
    exit 1
else
    echo "OK - Shorewall conf is fine."
    exit 0
fi
