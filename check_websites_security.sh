#!/bin/bash
#
# On big servers (above 50/100 websites) it would be too hard to check every URI on every website everytime.
# It could make thousands of http requests.
# So we store the curl output in a file in /var/tmp, and we increase the
# probability of recheck from 1 to 7 days old.
# After 7 days, tmp file is removed and recheck is mandatory.
#
# We do not store errors, so error urls are recheck every time.
#

# Must be ran by root
if [ "${USER}" != "root" ]; then
    echo "This script must be run as root."
    exit 3
fi

FREQUENCY=$((4*24)) # NB checks per day. Must be configured to set tests probabilities.

tmp_errors=$(mktemp "/tmp/$(basename "$0").XXXXXX")
export tmp_errors
tmp_checked=$(mktemp "/tmp/$(basename "$0").XXXXXX")
export tmp_checked
trap 'rm -f -- "$tmp_errors"' EXIT
trap 'rm -f -- "$tmp_checked"' EXIT

mkdir -p /var/tmp/check_websites_security

find /var/tmp/check_websites_security -type f -empty -delete
find /var/tmp/check_websites_security -type f -mtime +7 -delete

# shellcheck disable=SC2317
check_url() {
    url="$1"
    domain=$2
    port=$3
    level=$4
    url_tmp_file=/var/tmp/check_websites_security/${url//\//_}
    if [ -f "$url_tmp_file" ]; then
        url_last_check=$((($(date +%s) - $(date +%s -r "$url_tmp_file")) / 86400))
    if [ "$url_last_check" -gt 0 ]; then
        # 10% chance per day after 1 day, 20% after 2 days, 33% after 3 days, 50% after 4 days
        probability_of_check=$((FREQUENCY * (10 / url_last_check)))
        if [ "$((RANDOM % probability_of_check))" -eq 0 ]; then
            rm "$url_tmp_file"
        fi
    fi
    fi
    if ! [ -f "$url_tmp_file" ]; then
        LC_ALL=C curl -A "Sysnove check_websites_security" --max-time 15 -sI -X GET --resolve "$domain:$port:127.0.0.1" "$url" > "$url_tmp_file"
        echo "$url" >> "$tmp_checked"
        if grep -q '^HTTP.*200' "$url_tmp_file"; then
            if ! grep -iq '^content-type: text/html' "$url_tmp_file"; then
                echo "$level : $url is readable" >> "$tmp_errors"
                mv "$url_tmp_file" "$url_tmp_file.err" # Do not cache errors
            fi
        fi
    fi
}

# shellcheck disable=SC2317
check_uri() {
    domain=$1
    uri=$2
    level=$3
    check_url "http://$domain$uri" "$domain" 80 "$level"
    check_url "https://$domain$uri" "$domain" 443 "$level"
}

# shellcheck disable=SC2317
check_website() {
    website=$1

    #echo $website

    check_uri "$website" "/.htaccess" WARNING
    check_uri "$website" "/.git/config" WARNING
    check_uri "$website" "/var/log/system.log" WARNING
    check_uri "$website" "/.env" CRITICAL
    check_uri "$website" "/.env.local" CRITICAL
    check_uri "$website" "/.env.production" CRITICAL
    check_uri "$website" "/dump.sql" CRITICAL
}

export -f check_url
export -f check_uri
export -f check_website

#if [ -d "/usr/local/ispconfig" ]; then
#    echo "This script is disabled on ISPConfig servers."
#    exit 0
#fi

if [ -d "/etc/nginx/sites-enabled" ]; then
    websites=$(grep -hRE '^[^#]*[^\$#]server_name' /etc/nginx/sites-enabled | grep -v '_;' | sed 's/;//g' | sed 's/server_name//g' | sed 's/\*/wildcard/g' | xargs -n 1 | sort | uniq)
    server="Nginx"
fi

if [ -d "/etc/apache2/sites-enabled" ]; then
    # COMMENT I think we don't need to check ServerAlias because we follow redirections
    websites=$(grep -hRE '^[^#]*[^\$#]ServerName' /etc/apache2/sites-enabled/ | sed -nre 's/^\s*ServerName\s+([[:alnum:]_.-]+)\s*$/\1/Ip' | sed -re 's/^\*/wildcard/' | xargs -n 1 | sort | uniq)
    server="Apache2"
fi

#if [ "$(echo "$websites" | wc -w)" -gt 50 ]; then
#    echo "$(echo "$websites" | wc -w) websites detected. This script is disabled above 50."
#    exit 0
#fi

nb_websites=$(echo "$websites" | wc -w)

# shellcheck disable=SC2086
xargs -P 4 -I {} bash -c 'check_website "$@"' _ {} <<< $websites

#for website in $websites; do
#    check_website "$website" &
#done
#
#wait

NB_ERRORS=$(wc -l < "$tmp_errors")

if grep -q '^CRITICAL' "$tmp_errors"; then
    RET=2
elif grep -q '^WARNING' "$tmp_errors"; then
    RET=1
else
    RET=0
fi

if [ $RET -eq 0 ]; then
    echo "$nb_websites $server websites - Everything seems OK (took ${SECONDS}s to check $(wc -l < "$tmp_checked") URL)"
    cat "$tmp_checked"
else
    echo "$NB_ERRORS dangerous files found in $nb_websites $server websites"
    cat "$tmp_errors"
fi

rm "$tmp_errors"
rm "$tmp_checked"

exit $RET
