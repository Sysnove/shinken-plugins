#!/bin/bash

###
### This plugin checks varnishstat and
### returns req/s and cache hitrate in perfdata
###
### CopyLeft 2022 Guillaume Subiron <guillaume@sysnove.fr>
###
### Usage : check_varnishstat.sh 
###

LAST_RUN_FILE=/var/tmp/nagios/check_varnishstat_last_run

NAGIOS_USER=${SUDO_USER:-$(whoami)}
if ! [ -d "$(dirname "$LAST_RUN_FILE")" ]; then
    install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$LAST_RUN_FILE")"
fi

if [ -f "$LAST_RUN_FILE" ] && [ ! -O "$LAST_RUN_FILE" ]; then
    echo "UNKNOWN: $LAST_RUN_FILE is not owned by $USER"
    exit 3
fi

if varnishstat=$(varnishstat -j 2>&1); then
    now=$(date +%H:%M:%S)

    varnishstat_version=$(echo "$varnishstat" | jq ".version")
    if [ "$varnishstat_version" == "null" ]; then # V0
        cache_hit=$(echo "$varnishstat" | jq '."MAIN.cache_hit".value')
        cache_hitpass=$(echo "$varnishstat" | jq '."MAIN.cache_hitpass".value')
        cache_miss=$(echo "$varnishstat" | jq '."MAIN.cache_miss".value')
        n_object=$(echo "$varnishstat" | jq '."MAIN.n_object".value')
    elif [ "$varnishstat_version" -eq 1 ]; then
        cache_hit=$(echo "$varnishstat" | jq '.counters."MAIN.cache_hit".value')
        cache_hitpass=$(echo "$varnishstat" | jq '.counters."MAIN.cache_hitpass".value')
        cache_miss=$(echo "$varnishstat" | jq '.counters."MAIN.cache_miss".value')
        n_object=$(echo "$varnishstat" | jq '.counters."MAIN.n_object".value')
    else
        echo "UNNOWN - Varnishstat version $varnishstat_version is not managed."
        exit 3
    fi

    if [ "$cache_hit" == "null" ]; then
        echo "UNKNOWN - Could not find cache hit in varnishstat"
        exit 3
    fi

    old_cache_hit=-1
    old_cache_hitpass=-1
    old_cache_miss=-1
    # shellcheck disable=SC1090
    source "$LAST_RUN_FILE"

    echo "
old_cache_hit=$cache_hit
old_cache_hitpass=$cache_hitpass
old_cache_miss=$cache_miss
last_check=$now
" > "$LAST_RUN_FILE"

    if [ -z "$last_check" ] || [ "$old_cache_hit" -eq -1 ] || [ "$old_cache_hit" == "null" ]; then
        echo "UNKOWN - Variables missing in database, please run the check again."
        exit 3
    fi

    total_hit=$((cache_hit + cache_hitpass + cache_miss))
    old_total_hit=$((old_cache_hit + old_cache_hitpass + old_cache_miss))

    if [ $total_hit -lt $old_total_hit ]; then
        echo "UNKOWN - Total hit have shrink since last run, please run the check again."
        exit 3
    fi

    now_s=$(date -d "$now" +%s)
    last_check_s=$(date -d "$last_check" +%s)
    period_s=$(( now_s - last_check_s ))

    period_hit=$((total_hit - old_total_hit))

    if [ "$period_hit" -gt 0 ]; then
        hitrate=$((((cache_hit - old_cache_hit) * 100) / period_hit))
        reqpersec=$(bc <<< "scale=1; ($period_hit / $period_s)")
    else
        hitrate=100
        reqpersec=0
    fi

    perfdata="ReqPerSec=$reqpersec CacheHitrate=${hitrate}% Objects=${n_object}"

    varnishbackends=$(varnishadm backend.list | tail -n +2 | awk 'NF')
    varnishbackends_total=$(echo "$varnishbackends" | wc -l)
    varnishbackends_healthy=$(echo "$varnishbackends" | awk '{print $4}' | grep "healthy" -c)
    if [ "$varnishbackends_healthy" -eq 0 ]; then # Varnish 5
        varnishbackends_healthy=$(echo "$varnishbackends" | awk '{print $3}' | grep "Healthy" -c)
    fi

    if [ "$varnishbackends_healthy" -eq "$varnishbackends_total" ] && [ "$varnishbackends_healthy" -gt 0 ]; then
        echo "Varnish OK : $period_hit requests in ${period_s} seconds (cache hitrate ${hitrate}%, ${n_object} objects) | $perfdata"
        exit 0
    else
        echo "Varnish CRITICAL : $varnishbackends_healthy/$varnishbackends_total healthy backends | $perfdata"
        exit 2
    fi
else
    echo "UNKNOWN : varnishstat returned code $? : $varnishstat"
    exit 3
fi
