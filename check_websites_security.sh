#!/bin/bash

tmp_file=$(mktemp "/tmp/$(basename "$0").XXXXXX")
trap 'rm -f -- "$tmp_file"' EXIT

critical () {
    echo "CRITICAL : $1" >> "$tmp_file"
}

warning () {
    echo "WARNING : $1" >> "$tmp_file"
}

check_website() {
    website=$1
    if LC_ALL=C curl --max-time 5 -sL -A "Sysnove check_websites_security" "http://$website/.htaccess" | grep -Eq '(Rewrite|IfModule|SetEnv|Auth(Type|Name|UserFile)) '; then
        warning "http://$website/.htaccess is readable."
    fi

    if LC_ALL=C curl --max-time 5 -sL -A "Sysnove check_websites_security" "http://$website/.git/config" | grep -q '\[branch'; then
        critical "http://$website/.git/config is readable."
    fi

    if LC_ALL=C curl --max-time 5 -sL -A "Sysnove check_websites_security" "http://$website/.env" | grep '(_DB|DB_|HOST|PORT|REDIS|MONGO|MYSQL|environment|ENVIRONMENT)'; then
        critical "http://$website/.env is readable."
    fi

}

if [ -d "/usr/local/ispconfig" ]; then
    echo "This script is disabled on ISPConfig servers."
    exit 0
fi

if [ -d "/etc/nginx/sites-enabled" ]; then
    websites=$(grep -hRE '^[^#]*[^\$#]server_name' /etc/nginx/sites-enabled | grep -v '_;' | sed 's/;//g' | sed 's/server_name//g' | sed 's/\*/wildcard/g' | xargs -n 1 | sort | uniq)
    server="Nginx"
fi

if [ -d "/etc/apache2/sites-enabled" ]; then
    # COMMENT I think we don't need to check ServerAlias because we follow redirections
    websites=$(grep -hRE '^[^#]*[^\$#]ServerName' /etc/apache2/sites-enabled/ | sed 's/ServerName//g' | sed 's/\*/wildcard/g' | xargs -n 1 | sort | uniq)
    server="Apache2"
fi

for website in $websites; do
    check_website "$website" &
done

wait

NB_ERRORS=$(wc -l < "$tmp_file")

if grep '^CRITICAL' "$tmp_file"; then
    RET=2
elif grep '^WARNING' "$tmp_file"; then
    RET=1
else
    RET=0
fi

rm "$tmp_file"

if [ $RET -eq 0 ]; then
    echo "$(echo "$websites" | wc -w) $server websites checked - Everything seems OK"
else
    echo "$NB_ERRORS dangerous files found in $(echo "$websites" | wc -w) $server websites"
fi

exit $RET
