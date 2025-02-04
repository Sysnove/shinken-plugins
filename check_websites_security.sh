#!/bin/bash

tmp_file=$(mktemp "/tmp/$(basename "$0").XXXXXX")
trap 'rm -f -- "$tmp_file"' EXIT

check_url() {
    resp=$(LC_ALL=C curl -A "Sysnove check_websites_security" --max-time 5 -sIL -X GET "$1")
    if echo "$resp" | grep '^HTTP' | tail -n 1 | grep -q 200; then
        if ! echo "$resp" | grep -i '^content-type: ' | tail -n 1 | grep -q 'text/html'; then
            echo "$2 : $1 is readable" >> "$tmp_file"
        fi
    fi
}

check_website() {
    website=$1

    check_url "http://$website/.htaccess" WARNING
    check_url "http://$website/.git/config" WARNING
    check_url "http://$website/var/log/system.log" WARNING
    check_url "http://$website/.env" CRITICAL
    check_url "http://$website/.env.local" CRITICAL
    check_url "http://$website/.env.production" CRITICAL
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

if [ "$(echo "$websites" | wc -w)" -gt 50 ]; then
    echo "$(echo "$websites" | wc -w) websites detected. This script is disabled above 50."
    exit 0
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
