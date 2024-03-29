#!/usr/bin/env bash

#
# Description :
#
# This plugin checks the RAM on Linux.
#
# CopyLeft 2017 Guillaume Subiron <guillaume@sysnove.fr>
# Based upon Lukasz Gogolin's http://bitbucket.org/lgogolin/check_mem
#
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more details.
#
# v2 adds support for "Shared" memory (Shmem in /proc/meminfo) which can also lead to OOM
# 

#Set script name
SCRIPT=$(basename "${BASH_SOURCE[0]}")

#Set default values
WARN=95
CRIT=98

# help function
function printHelp {
  echo -e \\n"Help for $SCRIPT"\\n
  echo -e "Basic usage: $SCRIPT -w {warning} -c {critical}"\\n
  echo "Command switches are optional, default values for warning is 95% and critical is 98%"
  echo "-w - Sets warning value for Memory Usage. Default is 95%"
  echo "-c - Sets critical value for Memory Usage. Default is 98%"
  echo -e "-h  - Displays this help message"\\n
  echo -e "Example: $SCRIPT -w 80 -c 90"\\n
}

# regex to check is OPTARG an integer
re='^[0-9]+$'

while getopts :w:c:h FLAG; do
  case $FLAG in
    w)
      if ! [[ $OPTARG =~ $re ]] ; then
        echo "error: Not a number" >&2; exit 1
      else
        WARN=$OPTARG
      fi
      ;;
    c)
      if ! [[ $OPTARG =~ $re ]] ; then
        echo "error: Not a number" >&2; exit 1
      else
        CRIT=$OPTARG
      fi
      ;;
    h)
      printHelp
      exit 1
      ;;
    \?)
      echo -e \\n"Option - $OPTARG not allowed."
      printHelp
      exit 2
      ;;
  esac
done

shift $((OPTIND-1))




# shellcheck disable=SC2207
array=( $(grep -E '^(MemTotal|MemFree|Buffers|Cached|Shmem|SReclaimable|SUnreclaim)' /proc/meminfo |awk '{print $1 " " $2}' |tr '\n' ' ' |tr -d ':' |awk '{ printf("%i %i %i %i %i %i %i", $2, $4, $6, $8, $10, $12, $14) }') )

total_k=${array[0]}
free_k=${array[1]}
buffer_k=${array[2]}
cache_k=${array[3]}
shared_k=${array[4]}
slab_reclaimable_k=${array[5]}
slab_unreclaim_k=${array[6]}
# We consided reclaimable slab as cache. But we need to separate shared.
cache_k=$((cache_k + slab_reclaimable_k - shared_k))
#used_k=$((total_k - free_k - buffer_k - cache_k))
total_m=$((total_k / 1024))
free_m=$((free_k / 1024))
buffer_m=$((buffer_k / 1024))
cache_m=$((cache_k / 1024))
shared_m=$((shared_k / 1024))
used_m=$((total_m - free_m - buffer_m - cache_m - shared_m))
slab_unreclaim_m=$((slab_unreclaim_k / 1024))

# Shared is count as "used" because it is not reclaimable like cache.
# Shared + Used is what is causing OOM errors
used_and_shared_m=$((used_m + shared_m))
used_and_shared_pct=$(((100 * used_and_shared_m) / total_m))

slab_unreclaim_pct=$(((100 * slab_unreclaim_m) / total_m))

if [ $total_m -gt 1000 ]; then
    total_g=$(bc <<< "scale=1; $total_m/1024")
    used_and_shared_g=$(bc <<< "scale=1; $used_and_shared_m/1024")
    ratio_txt="$used_and_shared_g/$total_g GB"
else
    ratio_txt="$used_and_shared_m/$total_m MB"
fi

warn_m=$(((total_m * WARN)/100))
crit_m=$(((total_m * CRIT)/100))

if [ $slab_unreclaim_pct -ge "10" ]; then
    sunreclaim_msg="(WARNING: SlabUnreclaim=${slab_unreclaim_m}MB)"
fi

message="$used_and_shared_pct% used ($ratio_txt) $sunreclaim_msg| memory=${used_m}MB;$warn_m;$crit_m;0;$total_m shared=${shared_m}MB;;;0;$total_m cache=${cache_m}MB;;;0;$total_m buffer=${buffer_m}MB;;;0;$total_m"

if [ $used_and_shared_pct -ge "$CRIT" ]; then
  echo -e "Memory CRITICAL - $message"
  exit 2
elif [ $used_and_shared_pct -ge "$WARN" ] || [ $slab_unreclaim_pct -ge "10" ]; then
  echo -e "Memory WARNING - $message"
  exit 1
else
  echo -e "Memory OK - $message"
  exit 0
fi
