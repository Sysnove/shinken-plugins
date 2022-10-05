#!/bin/bash

###
### This plugin checks the RAM of a given processus Linux.
###
### CopyLeft 2021 Guillaume Subiron <guillaume@sysnove.fr>
### Based upon Denny's http://www.dennyzhang.com/nagois_monitor_process_memory
###
### This work is free. You can redistribute it and/or modify it under the
### terms of the Do What The Fuck You Want To Public License, Version 2,
### as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more details.
###
### Usage: 
### - check_proc_mem.sh -w 1024 -c 2048 --cmdpattern "tomcat7.*java.*Dcom"
### - check_proc_mem.sh -w 1024 -c 2048 --pidfile /var/run/tomcat7.pid
### - check_proc_mem.sh -w 1024 -c 2048 --pid 11325
### - check_proc_mem.sh -W 50 -C 80 --pid 11325 # warn and crit in pct.
### 

usage() {
    sed -rn 's/^### ?//;T;p' "$0"
}

TOTAL_MEM=$(LANG=C free -m|awk '/^Mem:/{print $2}')

while [ $# -gt 0 ]; do
    case "$1" in
        -w|--warn) shift
            WARN=$1
            ;;
        -c|--crit) shift
            CRIT=$1
            ;;
        -W) shift
            WARN_PCT=$1
            WARN=$(((TOTAL_MEM*WARN_PCT)/100))
            ;;
        -C) shift
            CRIT_PCT=$1
            CRIT=$(((TOTAL_MEM*CRIT_PCT)/100))$1
            ;;
        --cmdpattern) shift
            CMDPATTERN=$1
            if ! PID=$(pgrep -o -f "$CMDPATTERN"); then
                echo "No processus found matching $CMDPATTERN."
                exit 3
            fi
            ;;
        --pidfile) shift
            PIDFILE=$1
            if [ -f "$PIDFILE" ]; then
                PID=$(cat "$PIDFILE")
            else
                echo "File $PIDFILE does not exist."
                exit 3
            fi
            ;;
        --pid) shift
            PID=$1
            ;;
        -h|--help) usage
            exit 0
            ;;
        *) echo "Unknown argument: $1"
            usage
            exit 3
            ;;
    esac
    shift
done

if [ -z "$WARN" ] || [ -z "$CRIT" ]; then
    echo "-w and -c are mandatory arguments."
    usage
    exit 3
fi

if [ "$WARN" -gt "$CRIT" ]; then
    echo "CRIT should be greater than WARN."
    exit 3
fi

if [ -z "$PID" ]; then
    echo "You need to use --pid, --pidfile or --cmdpattern."
    usage
    exit 3
fi

if ! [ -f "/proc/$PID/status" ]; then
    echo "Processus $PID is not running."
    exit 3
fi

memVmSize=$(grep 'VmSize:' "/proc/$PID/status" | awk -F' ' '{print $2}')
memVmSize=$((memVmSize/1024))

memVmRSS=$(grep 'VmRSS:' "/proc/$PID/status" | awk -F' ' '{print $2}')
memVmRSS=$((memVmRSS/1024))

if [ "$memVmRSS" -ge "$CRIT" ]; then
    echo "Memory: CRITICAL VIRT: $memVmSize MB - RES: $memVmRSS MB used!|RES=${memVmRSS}MB;$WARN;$CRIT;0;"
    exit 2
elif [ "$memVmRSS" -ge "$WARN" ]; then
    echo "Memory: WARNING VIRT: $memVmSize MB - RES: $memVmRSS MB used!|RES=${memVmRSS}MB;$WARN;$CRIT;0;"
    exit 1
else
    echo "Memory: OK VIRT: $memVmSize MB - RES: $memVmRSS MB used!|RES=${memVmRSS}MB;$WARN;$CRIT;0;"
    exit 0
fi
