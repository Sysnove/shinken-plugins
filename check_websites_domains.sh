#!/bin/bash

###
### This script checks the expiration date for every Nginx or Apache2 vhosts.
### It can be used as a nagios plugin, or in a cron to send an email.
###
### CopyLeft 2022 Guillaume Subiron <guillaume@sysnove.fr>
###
### This work is free. You can redistribute it and/or modify it under the 
### terms of the Do What The Fuck You Want To Public License, Version 2, 
### as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more details.
###
### Usage :
###

SCRIPT=$(basename "${BASH_SOURCE[0]}")

CACHE_DIR="/var/tmp/$USER/check_domain"

mkdir -p "$CACHE_DIR"

VERBOSE=false
NAGIOSMODE=false
EMAIL=""

WARNING=7

usage() {
    sed -rn 's/^### ?//;T;p' "$0"
}

info() {
    if $VERBOSE || $NAGIOSMODE; then
        echo "$@"
    fi
}

debug() {
    if $VERBOSE; then
        echo "$@"
    fi
}

while getopts "vcnhe:w:" option; do
    case $option in
        v)
            VERBOSE=true
            ;;
        n)
            NAGIOSMODE=true
            ;;
        e)
            EMAIL=$OPTARG
            ;;
        w)
            WARNING=$OPTARG
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument $option;"
            usage
            exit 3
            ;;
    esac
done

if $NAGIOSMODE && [ -n "$EMAIL" ]; then
    echo "-n and -e options are incompatible. Please choose one or the other"
    usage
    exit 3
fi


if [ -d "/etc/nginx/sites-enabled" ]; then
    # Sysnove: The Oneliner Company.
    domains=$(grep -hRE '^[^#]*[^\$#]server_name' /etc/nginx/sites-enabled | grep -v '_;' | sed 's/;//g' | sed 's/server_name//g' | sed 's/\*/wildcard/g' | xargs -n 1 | grep -v '^default$' | grep -v 'sysnove.net$' | awk -F/ '{n=split($1, a, "."); printf("%s.%s\n", a[n-1], a[n])}' | grep -v '^\.$' | sort | uniq)
    #server="Nginx"
fi

if [ -d "/etc/apache2/sites-enabled" ]; then
    domains=$(grep -hRE '^[^#]*[^\$#]Server(Name|Alias)' /etc/apache2/sites-enabled/ | sed 's/Server(Name|Alias)//g' | sed 's/\*/wildcard/g' | xargs -n 1 | grep -v '^default$' | grep -v 'sysnove.net$' | awk -F/ '{n=split($1, a, "."); printf("%s.%s\n", a[n-1], a[n])}' | grep -v '^\.$' | sort | uniq)
    #server="Apache2"
fi

TOTAL_DOMAINS=0
TOTAL_WARNING=0
TOTAL_ERROR=0
TOTAL_UNKNOWN=0

errors=""
warnings=""

nb_domains=$(echo "$domains" | wc -w)
if [ "$nb_domains" -gt 200 ]; then
    info "UNKNOWN : More than 200 domains to check ($nb_domains), abording."
    exit 3
fi

for domain in $domains; do
    if [[ $domain == *.eu ]] || [[ $domain == *.ch ]]; then
        debug "UNKNOWN - Cannot check $domain because whois does not provide expiration date."
        TOTAL_UNKNOWN=$((TOTAL_UNKNOWN+1))
        continue
    fi

    output=$(/usr/local/nagios/plugins/check_domain.sh -C "$CACHE_DIR" -a 30 -w "$WARNING" -c 0 -d "$domain")
    ret=$?
    output=$(echo "$output" | cut -d '|' -f 1)

    TOTAL_DOMAINS=$((TOTAL_DOMAINS+1))

    if [ $ret -ne 0 ]; then
        if [ $ret -eq 3 ]; then
            if [ "$output" == 'UNKNOWN - There is no domain name to check' ]; then
                ret=2
                output="${output/UNKNOWN/CRITICAL}"
            else
                info "$output"
                TOTAL_UNKNOWN=$((TOTAL_UNKNOWN+1))
            fi
        fi
        if [ $ret -eq 2 ]; then
            info "$output"
            TOTAL_ERROR=$((TOTAL_ERROR+1))
            errors="$errors- $output\\n"
        fi
        if [ $ret -eq 1 ]; then
            info "$output"
            TOTAL_WARNING=$((TOTAL_WARNING+1))
            warnings="$warnings- $output\\n"
        fi
    fi
done

if [ -d '/usr/local/ispconfig' ]; then
    solution="en désactivant les sites dans le panel ISPConfig."
else
    solution="en nous demandant de désactiver ce nom de domaine."
fi

if $NAGIOSMODE; then
    if [ $TOTAL_UNKNOWN -gt 0 ]; then
        unknown_str="($TOTAL_UNKNOWN could not be checked)"
    fi

    if [ $TOTAL_ERROR -gt 0 ] ; then
        echo "CRITICAL - $TOTAL_ERROR domains are expired ($TOTAL_WARNING warning and $TOTAL_DOMAINS ok) $unknown_str"
        exit 2;
    elif [ $TOTAL_WARNING -gt 0 ] ; then
        echo "WARNING - $TOTAL_WARNING domains will expire in the next $WARNING days, $TOTAL_DOMAINS ok $unknown_str"
        exit 1;
    else
        echo "OK - $TOTAL_DOMAINS up to date $unknown_str"
        exit 0;
    fi
else
    if [ -n "$errors" ] || [ -n "$warnings" ]; then
        body="Bonjour,

Certains noms de domaine configurés sur $(hostname) ont expiré ou vont
expirer dans la semaine :

$warnings
$errors

Nous vous laissons le soin de corriger ces problèmes en renouvelant les
noms de domaine ou $solution

Si vous avez besoin d'aide, ou si vous ne souhaitez pas recevoir ces
avertissements, n'hésitez pas à repondre à cet email.

-- 
Email automatique envoyé par le script $(hostname):$SCRIPT
        "

        if [ -n "$EMAIL" ]; then
            /usr/local/bin/send-msg-to-client-email --to "$EMAIL" --subject "[$(hostname)] Avertissement d'expiration de noms de domaine" --body "$body" --copy-to-from
        else
            echo ""
            echo "The following email could be sent to the client if you use the '-e' option to specify an email address."
            echo ""
            echo "$body"
        fi
    fi
fi
