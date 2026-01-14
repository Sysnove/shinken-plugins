#!/bin/bash

# Checks for security.conf snippet in Nginx vhosts on port 8080.
# Because 403 and 429 returned by security.conf could be cached by Varnish and then returned to everyone.
nginx_security_warnings=$(grep -RE '^ *(listen|include snippets/security.conf)' /etc/nginx/sites-enabled | grep 'include snippets' -B 1 | grep ':8080' -A 1 | cut -d ':' -f 1 | uniq)
if [ -n "$nginx_security_warnings" ]; then
    echo "WARNING - You should not use Nginx security.conf snippet in a vhost on port 8080."
    echo "$nginx_security_warnings"
    exit 1
fi

# :TODO:maethor:20260114: Check log format to force timed_combined?

echo "OK - Nginx config is all good."
exit 0
