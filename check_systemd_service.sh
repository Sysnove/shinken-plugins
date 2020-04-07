#!/bin/bash

[ -z "$1" ] && { 
   echo 'Use:'
   echo "$0 unit"
   echo
   echo "Will check if the specified unit is active, and alert if not"
   exit 1
}

result=$(systemctl is-active "$1")
rc=$?

if [ $rc -eq 0 ]; then
   echo "OK: $1 is $result"
   exit 0
else
   echo "CRITICAL: $1 is $result"
   exit 2
fi

