#!/bin/bash
#
# Simple Nagios check for nvme using nvme-cli
# Author: Sam McLeod https://smcleod.net
#
# Requirements:
# nvme-cli - git clone https://github.com/linux-nvme/nvme-cli
#
# Usage:
# ./check_nvme.sh [device name]

device=$1

DISKS=${device:=$(lsblk -e 11,253 -dn -o NAME | grep nvme)}
CRIT=false
MESSAGE=""

NVME_CMD="sudo nvme"

for DISK in $DISKS ; do
  # Check for critical_warning
  $(${NVME_CMD} smart-log /dev/$DISK | awk 'FNR == 2 && $3 != 0 {exit 1}')
  if [ $? == 1 ]; then
    CRIT=true
    MESSAGE="$MESSAGE $DISK has critical warning "
  fi

  # Check media_errors
  $(${NVME_CMD} smart-log /dev/$DISK | awk 'FNR == 15 && $3 != 0 {exit 1}')
  if [ $? == 1 ]; then
    CRIT=true
    MESSAGE="$MESSAGE $DISK has media errors "
  fi

  # Check num_err_log_entries
  $(${NVME_CMD} smart-log /dev/$DISK | awk 'FNR == 16 && $3 != 0 {exit 1}')
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
