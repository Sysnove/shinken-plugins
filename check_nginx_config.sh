#!/bin/bash

# Checks for security.conf snippet in Nginx vhosts on port 8080.
# Because 403 and 429 returned by security.conf could be cached by Varnish and then returned to everyone.
nginx_security_warnings=$(grep -RE '^ *(listen|include snippets/security.conf)' /etc/nginx/sites-enabled | grep 'include snippets' -B 1 | grep ':8080' -A 1 | cut -d ':' -f 1 | uniq)
if [ -n "$nginx_security_warnings" ]; then
    echo "$nginx_security_warnings"
    echo "WARNING - You should not use Nginx security.conf snippet in a vhost on port 8080."
    exit 1
fi

# Test that magento /media/ location is not in 8080 vhost
nginx_media_warnings=$(grep -RE '^ *(listen|location /media/ {)' /etc/nginx/sites-enabled | grep 'location /media/' -B 1 | grep ':8080' | cut -d ':' -f 1)
if [ -n "$nginx_media_warnings" ]; then
    echo "$nginx_media_warnings"
    echo "WARNING - You should not define /media/ location in 8080 magento's vhost. It should be before Varnish."
    exit 1
fi

# Check log format to force timed_combined
nginx_logs_warnings=$(grep -REl '^ *access_log.*\.log( combined)?;' /etc/nginx/sites-enabled | xargs -L1 basename)
if [ -n "$nginx_logs_warnings" ]; then
    echo "$nginx_logs_warnings"
    echo "WARNING - Some vhosts are not configured with access_log timed_combined."
    exit 1
fi

echo "OK - Nginx config is all good."
exit 0
