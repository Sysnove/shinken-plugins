#!/bin/bash
#
# Simple Nagios check for nvme using nvme-cli
# Author: Sam McLeod https://smcleod.net
#
# Requirements:
# nvme-cli - git clone https://github.com/linux-nvme/nvme-cli
#
# Usage:
# ./check_nvme.sh

DISKS=$(lsblk -e 11,253 -dn -o NAME | grep nvme)
CRIT=false
MESSAGE=""

for DISK in $DISKS ; do
  # Check for critical_warning
  $(nvme smart-log /dev/$DISK | awk 'FNR == 2 && $3 != 0 {exit 1}')
  if [ $? == 1 ]; then
    CRIT=true
    MESSAGE="$MESSAGE $DISK has critical warning "
  fi

  # Check media_errors
  $(nvme smart-log /dev/$DISK | awk 'FNR == 15 && $3 != 0 {exit 1}')
  if [ $? == 1 ]; then
    CRIT=true
    MESSAGE="$MESSAGE $DISK has media errors "
  fi

  # Check num_err_log_entries
  $(nvme smart-log /dev/$DISK | awk 'FNR == 16 && $3 != 0 {exit 1}')
  if [ $? == 1 ]; then
    CRIT=true
    MESSAGE="$MESSAGE $DISK has errors logged "
  fi
done

if [ $CRIT = "true" ]; then
  echo "CRITICAL: $MESSAGE"
  exit 2
else
  echo "OK $(echo $DISKS | tr -d '\n')"
  exit 0
fi
