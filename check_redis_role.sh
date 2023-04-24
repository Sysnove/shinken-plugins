#!/bin/bash

if [ -n "$1" ]; then
    REDIS_PORT="$1"
else
    REDIS_PORT="6379"
fi

REDIS_CONF="$(grep -R -l "^port ${REDIS_PORT}$" /etc/redis | head -n 1)"

if [ -z "$REDIS_CONF" ]; then
    echo "UNKNOWN: Unable to find redis conf for port $REDIS_PORT"
    exit 3
fi

REDIS_PASS=$(grep '^requirepass' "$REDIS_CONF" | awk '{print $2}' | sed 's/"//g')

if [ -n "$REDIS_PASS" ]; then
    REDIS_COMMAND="redis-cli --no-auth-warning -a ${REDIS_PASS} -p ${REDIS_PORT}"
else
    REDIS_COMMAND="redis-cli -p ${REDIS_PORT}"
fi

if ! server_info=$($REDIS_COMMAND info server 2>&1); then
    echo "CRITICAL: $server_info"
    exit 2
fi

info=$($REDIS_COMMAND INFO)

if echo "$info" | grep -q "redis_mode:sentinel"; then
    nb_masters_ok=0
    nb_masters_nok=0
    for master in $(echo "$info" | grep "^master"); do
        if echo "$master" | grep -q "status=ok"; then
            nb_masters_ok=$((nb_masters_ok+1))
        else
            echo "$master"
            nb_masters_nok=$((nb_masters_nok+1))
        fi
    done

    if [ $nb_masters_nok -gt 0 ]; then
        echo "CRITICAL: Redis $REDIS_PORT is a Sentinel with $nb_masters_nok masters not OK ($nb_masters_ok OK)"
        exit 2
    else
        echo "OK: Redis $REDIS_PORT is a Sentinel with $nb_masters_ok masters"
        exit 0
    fi
else
    replication_info=$($REDIS_COMMAND info replication)

    role=$(echo "$replication_info" | grep '^role:' | cut -d ':' -f 2 | grep -o '[a-z0-9\.]*')
    connected_slaves=$(echo "$replication_info" | grep '^connected_slaves:' | cut -d ':' -f 2 | grep -o '[a-z0-9\.]*')

    if [ "$role" == "master" ]; then
        echo "OK: Redis $REDIS_PORT is master with $connected_slaves connected slave(s)"
    elif [ "$role" == "slave" ]; then
        lag=$($REDIS_COMMAND --latency --raw | awk '{print $3}')
        master_host=$(echo "$replication_info" | grep '^master_host:' | cut -d ':' -f 2 | grep -o '[a-z0-9\.]*')
        master_port=$(echo "$replication_info" | grep '^master_port:' | cut -d ':' -f 2 | grep -o '[a-z0-9\.]*')
        master="$master_host:$master_port"
        if (( $(echo "$lag > 10" |bc -l) )); then
            echo "WARNING: Redis $REDIS_PORT is slave and ${lag}ms late on master ($master)"
            exit 1
        else
            echo "OK: Redis $REDIS_PORT is slave and connected to $master (${lag}ms lag)"
            exit 0
        fi
    else
        echo "UNKNOWN: Redis $REDIS_PORT role is $role"
        exit 3
    fi
fi

