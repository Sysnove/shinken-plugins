#!/bin/bash

RET=0 # OK

critical () {
    echo "SECURITY CRITICAL : $1"
    RET=2
}

warning () {
    echo "SECURITY WARNING : $1"
    [ $RET -eq 0 ] && RET=1
}

check_website() {
    domain=$1
    if LC_ALL=C curl --max-time 1 -sL "http://$domain/.env" | grep '(_DB|DB_|HOST|PORT|REDIS|MONGO|MYSQL|environment|ENVIRONMENT)'; then
        critical "http://$domain/.env is readable."
    fi

    if LC_ALL=C curl --max-time 1 -sL "http://$domain/.htaccess" | grep -Eq '(Rewrite|IfModule|ErrorDocument|SetEnv|Auth(Type|Name|UserFile)|Require) '; then
        critical "http://$domain/.htaccess is readable."
    fi

    if LC_ALL=C curl --max-time 1 -sL "http://$domain/.git/config" | grep -q '\[branch'; then
        critical "http://$domain/.git/config is readable."
    fi
}

if [ -d "/etc/nginx/sites-enabled" ]; then
    for domain in $(grep -hRE '^[^#]*[^\$#]server_name' /etc/nginx/sites-enabled | grep -v '_;' | sed 's/;//g' | sed 's/server_name//g' | xargs -n 1 | sort | uniq); do
        check_website "$domain"
    done
fi

if [ -d "/etc/apache2/sites-enabled" ]; then
    # COMMENT I think we don't need to check ServerAlias because we follow redirections
    for domain in $(grep -hRE '^[^#]*[^\$#]ServerName' /etc/apache2/sites-enabled/ | sed 's/ServerName//g' | xargs -n 1 | sort | uniq); do
        check_website "$domain"
    done
fi


if [ $RET -eq 0 ]; then
    echo "Everything seems OK"
fi

exit $RET