#!/bin/bash

if [ -n "$1" ]; then
    REDIS_PORT="$1"
else
    REDIS_PORT="6379"
fi

if [ -n "$2" ]; then
    REDIS_DB="$2"
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

if [ -z "$REDIS_DB" ]; then
    for REDIS_DB in $(seq 1 15); do
        queues=$($REDIS_COMMAND -n "$REDIS_DB" smembers queues)
        if [ -n "$queues" ]; then
            break
        fi
    done
fi

queues=$($REDIS_COMMAND -n "$REDIS_DB" smembers queues)

if [ -z "$queues" ]; then
    echo "UNKNOWN : No queue found"
    exit 3
fi

total_size=0
perfdata=""

for queue in $queues; do
    size=$($REDIS_COMMAND -n "$REDIS_DB" llen "queue:$queue" | cut -d " " -f 1)
    total_size=$((total_size + size))
    perfdata="$perfdata $queue=$size"
done

msg="$total_size jobs waiting in sidekiq queue (redis://localhost:$REDIS_PORT/$REDIS_DB) | $perfdata"

if [ "$total_size" -gt 1000 ]; then
    echo "WARNING : $msg"
    exit 1
else
    echo "OK : $msg"
    exit 0
fi
