#!/usr/bin/env bash

#
# Description :
#
# This plugin checks the SWAP on Linux.
#
# CopyLeft 2017 Guillaume Subiron <guillaume@sysnove.fr>
# Based upon Lukasz Gogolin's http://bitbucket.org/lgogolin/check_mem
#
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more details.
# 

#Set script name
SCRIPT=`basename ${BASH_SOURCE[0]}`

#Set default values
WARN=95
CRIT=98

# help function
function printHelp {
  echo -e \\n"Help for $SCRIPT"\\n
  echo -e "Basic usage: $SCRIPT -w {warning} -c {critical}"\\n
  echo "Command switches are optional, default values for warning is 95% and critical is 98%"
  echo "-w - Sets warning value for Swap Usage. Default is 95%"
  echo "-c - Sets critical value for Swap Usage. Default is 98%"
  echo -e "-h  - Displays this help message"\\n
  echo -e "Example: $SCRIPT -w 80 -c 90"\\n
  exit 1
}

# regex to check is OPTARG an integer
re='^[0-9]+$'

while getopts :w:c:W:C:h FLAG; do
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
      ;;
    \?)
      echo -e \\n"Option - $OPTARG not allowed."
      printHelp
      exit 2
      ;;
  esac
done

shift $((OPTIND-1))





array=( $(cat /proc/meminfo | egrep 'MemTotal|MemFree|Buffers|Cached|SwapTotal|SwapFree' |awk '{print $1 " " $2}' |tr '\n' ' ' |tr -d ':' |awk '{ printf("%i %i %i %i %i %i %i", $2, $4, $6, $8, $10, $12, $14) }') )

total_k=${array[5]}
total_b=$(($total_k*1024))
free_k=${array[6]}
free_b=$(($free_k*1024))
used_k=$(($total_k-$free_k))
used_b=$(($used_k*1024))
total_m=$(($total_k/1024))
free_m=$(($free_k/1024))
used_m=$(($total_m-$free_m))

if [ $total_m > 1000 ]; then
    total_g=$(bc <<< "scale=1; $total_m/1024")
    used_g=$(bc <<< "scale=1; $used_m/1024")
    ratio_txt="$used_g/$total_g GB"
else
    ratio_txt="$used_m/$total_m MB"
fi

warn_m=$((($total_m*$WARN)/100))
crit_m=$((($total_m*$CRIT)/100))

if [ $total_k -eq 0 ]; then
    used_pct=0
else
    used_pct=$((($used_k*100)/$total_k))
fi

message="$used_pct% used ($ratio_txt) | swap=${used_m}MB;$warn_m;$crit_m;0;$total_m"


if [ $used_pct -ge $CRIT ]; then
  echo -e "SWAP CRITICAL - $message"
  $(exit 2)
elif [ $used_pct -ge $WARN ]; then
  echo -e "SWAP WARNING - $message"
  $(exit 1)
else
  echo -e "SWAP OK - $message"
  $(exit 0)
fi
