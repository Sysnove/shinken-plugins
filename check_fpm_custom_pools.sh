#!/bin/bash

ret=0

for conf in $(find /etc/php | grep 'pool.d/.*.conf$' | grep -v '/www.conf$' | grep -v '/web.*.conf$' | grep -v '/apps.conf$' | grep -v '/ispconfig.conf$'); do
    listen=$(cat "$conf" | grep '^listen =' | awk '{print $3}')
    if ! grep -qR "$listen" /etc/nginx && ! grep -qR "$listen" /etc/apache2; then
        echo "WARNING - $listen pool defined by $conf is not used"
        ret=1
        continue
    fi

    if ! grep '^access.log = /var/log/php-fpm/access.log' "$conf"; then
        echo "WARNING - access.log is not configured in $conf"
        ret=1
        continue
    fi

    for var in request_terminate_timeout access.format; do
        if ! grep "^$var" "$conf"; then
            echo "WARNING - $var is not configured in $conf"
            ret=1
            continue
        fi
    done

done

if [ $ret -eq 0 ]; then
    echo "OK - All FPM custom pools are well configured."
fi

exit $ret
