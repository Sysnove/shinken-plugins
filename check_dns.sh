#!/bin/bash

# Nagios's check_dns uses nxlookup and time mesured can be very slow when the host is under load.
# On an empty host, we typically get 60ms with Nagios's check_dns, and 0 to 15ms with this plugin.

###
### Usage: check_dns.sh -H google.com -w 0.1 -c 0.3
###

warn_s=0.1
crit_s=0.3

usage() {
    sed -rn 's/^### ?//;T;p' "$0"
}

while [ $# -gt 1 ]; do
    case "$1" in
        -H) shift
            domain=$1
            ;;
        -w) shift
            warn_s=$1
            ;;
        -c) shift
            crit_s=$1
            ;;
        -h|--help) usage
            exit 0
            ;;
        *) echo "UNKNOWN argument : $1"
            usage
            exit 3
            ;;
    esac
    shift
done

if [ -z "$domain" ]; then
    usage
    exit 3
fi

warn_ms=$(echo "scale=0; $warn_s*1000" | bc | cut -d '.' -f 1)
crit_ms=$(echo "scale=0; $crit_s*1000" | bc | cut -d '.' -f 1)

out="$(dig "$domain")"
status="$(echo "$out" | grep -Eo 'status: [^,]+' | cut -d ' ' -f 2)"

if [ "$status" != "NOERROR" ]; then
    echo "DNS UNKNOWN: dig $domain returned $status"
    exit 3
fi

server=$(echo "$out" | grep 'SERVER:' | awk '{print $3}' | cut -d '#' -f 1)
response=$(echo "$out" | grep 'ANSWER SECTION:' -A 1 | tail -n 1 | xargs)

time_ms=$(echo "$out" | grep 'Query time:' | awk '{print $4}')
time_s=$(echo "scale=3; $time_ms/1000" | bc)

msg="${time_ms}ms response time from $server: $response | time=$time_s;$warn_s;$crit_s;0"

if [ "$time_ms" -ge "$crit_ms" ]; then
    echo "DNS CRITICAL: $msg"
    exit 2
elif [ "$time_ms" -ge "$warn_ms" ]; then
    echo "DNS WARNING: $msg"
    exit 1
else
    echo "DNS OK: $msg"
    exit 0
fi
