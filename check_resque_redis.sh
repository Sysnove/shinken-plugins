#!/usr/bin/env bash

#
# Description :
#
# This plugin checks the size of a Resque queue.
#
# CopyLeft 2020 Guillaume Subiron <guillaume@sysnove.fr>
#
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more details.
#

E_OK=0
E_WARNING=1
E_CRITICAL=2
E_UNKNOWN=3

REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0

WARN=5
CRIT=10

show_usage() {
    echo "$0 [-h REDIS_HOST] [-p REDIS_PORT] [-n REDIS_BASE] [-w warn_threshold] [-c crit_threshold]"
}

while getopts "h:p:n:w:c:" option
do
    case $option in
        h)
            REDIS_HOST=$OPTARG
            ;;
        p)
            REDIS_PORT=$OPTARG
            ;;
        n)
            REDIS_DB=$OPTARG
            ;;
        w)
            WARN=$OPTARG
            ;;
        c)
            CRIT=$OPTARG
            ;;
        *)
            usage
            ;;
    esac
done


resque_keys=$(timeout 3 redis-cli -h $REDIS_HOST -p $REDIS_PORT -n $REDIS_DB keys resque:*)

if [ $? != 0 ]; then
    echo "UNKNOWN - Error connecting to redis $REDIS_HOST:$REDIS_PORT"
    exit $E_UNKNOWN
fi

if [ -z "$resque_keys" ]; then
    echo "UNKNOWN - No resque keys found on redis $REDIS_HOST:$REDIS_PORT and db $REDIS_DB"
    exit $E_UNKNOWN
fi

workers=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT -n $REDIS_DB scard resque:workers)

if [ $workers -eq 0 ]; then
    echo "CRITICAL - No worker registered in resque"
    exit $E_CRITICAL
fi

processed=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT -n $REDIS_DB get resque:stat:processed)
errors=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT -n $REDIS_DB llen resque:failed)

queues=$(redis-cli -h $REDIS_HOST -p $REDIS_PORT -n $REDIS_DB scard resque:queues)

sum=0

for s in $(redis-cli -h $REDIS_HOST -p $REDIS_PORT -n $REDIS_DB keys resque:queue:*)
do
    sum=$(($sum+$(redis-cli -h $REDIS_HOST -p $REDIS_PORT -n $REDIS_DB llen $s)))
done

out="$sum jobs queued in $queues queues ($workers workers, $processed processed, $errors errors)"

if [ $sum -ge $CRIT ]; then
    echo "CRITICAL - $out"
    exit $E_CRITICAL
fi

if [ $sum -ge $WARN ]; then
    echo "WARNING - $out"
    exit $E_WARNING
fi

echo "OK - $out"
exit $E_OK
