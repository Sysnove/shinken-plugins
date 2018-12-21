#!/bin/bash
#template from http://www.juliux.de/nagios-plugin-vorlage-bash
WARN_LIMIT=$1
CRIT_LIMIT=$2
if [ -z $WARN_LIMIT ] || [ -z $CRIT_LIMIT ];then
  echo "Usage: check_linux_raid_mismatch WARNLIMIT CRITLIMIT"
  exit 3;
else
  DATA=-1
  for file in /sys/block/md*/md/mismatch_cnt
  do
    DATA2=`cat $file`
    DATA=$((DATA + DATA2))
    MD_NAME=`echo $file | awk 'BEGIN { FS = "/" } ; { print $4 }'`
    PERF_DATA+="$MD_NAME=`cat $file` "
  done
  if [ $DATA -lt $WARN_LIMIT ]; then
    echo "OK - all software raid mismatch_cnts are smaller than $WARN_LIMIT | $PERF_DATA"
    exit 0;
  fi
  if [ $DATA -ge $WARN_LIMIT ] && [ $DATA -lt $CRIT_LIMIT ]; then
    echo "WARNING - software raid mismatch_cnts are greater or equal than $WARN_LIMIT | $PERF_DATA"
    exit 1;
  fi
  if [ $DATA -ge $CRIT_LIMIT ]; then
    echo "CRITICAL - software raid mismatch_cnts are greater or equal than $CRIT_LIMIT | $PERF_DATA"
    exit 2;
  fi
  if [ $DATA -eq -1 ]; then
    echo "UNKNOWN - software raid mismatch_cnts not found | $PERF_DATA"
    exit 3;
  fi
fi
