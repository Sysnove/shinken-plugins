#!/bin/bash -e
##-------------------------------------------------------------------
## File: check_proc_mem.sh
## Author : Denny
## Description :
## --
##
## Link: http://www.dennyzhang.com/nagois_monitor_process_memory
##
## Created :
## Updated: Time-stamp:
##-------------------------------------------------------------------
SCRIPTNAME=$(basename $0)

if [ "$1" = "-w" ] && [ "$2" -gt "0" ] && \
    [ "$3" = "-c" ] && [ "$4" -gt "0" ]; then
pidPattern=${5?"specify how to get pid"}

if [ "$pidPattern" = "--pidfile" ]; then
    pidfile=${6?"pidfile to get pid"}
    pid=$(cat $pidfile)
elif [ "$pidPattern" = "--cmdpattern" ]; then
    cmdpattern=${6?"command line pattern to find out pid"}
    pid=$(ps -ef | grep "$cmdpattern" | grep -v grep | grep -v ${SCRIPTNAME} | head -n 1 | awk -F' ' '{print $2}')
elif [ "$pidPattern" = "--pid" ]; then
    pid=${6?"pid"}
else
    echo "ERROR input for pidpattern"
    exit 2
fi

if [ -z "$pid" ]; then
    echo "ERROR: no related process is found"
    exit 2
fi

memVmSize=`grep 'VmSize:' /proc/$pid/status | awk -F' ' '{print $2}'`
memVmSize=$(($memVmSize/1024))

memVmRSS=`grep 'VmRSS:' /proc/$pid/status | awk -F' ' '{print $2}'`
memVmRSS=$(($memVmRSS/1024))

if [ "$memVmRSS" -ge "$4" ]; then
    echo "Memory: CRITICAL VIRT: $memVmSize MB - RES: $memVmRSS MB used!|RES=${memVmRSS}MB;$2;$4;0;"
    $(exit 2)
elif [ "$memVmRSS" -ge "$2" ]; then
    echo "Memory: WARNING VIRT: $memVmSize MB - RES: $memVmRSS MB used!|RES=${memVmRSS}MB;$2;$4;0;"
    $(exit 1)
else
    echo "Memory: OK VIRT: $memVmSize MB - RES: $memVmRSS MB used!|RES=${memVmRSS}MB;$2;$4;0;"
    $(exit 0)
fi

else
    echo "${SCRIPTNAME}"
    echo ""
    echo "Usage:"
    echo "${SCRIPTNAME} -w -c "
    echo ""
    echo "Below: If tomcat use more than 1024MB resident memory, send warning"
    echo "${SCRIPTNAME} -w 1024 -c 2048 --pidfile /var/run/tomcat7.pid"
    echo "${SCRIPTNAME} -w 1024 -c 2048 --pid 11325"
    echo "${SCRIPTNAME} -w 1024 -c 2048 --cmdpattern \"tomcat7.*java.*Dcom\""
    echo ""
    echo "Copyright (C) 2014 DennyZhang (denny.zhang001@gmail.com)"
    exit
fi
## File - check_proc_mem.sh ends
