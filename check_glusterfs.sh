#!/bin/bash


usage () {
	echo ""
	echo "USAGE: "
	echo "  $PROGNAME [-w GB -c GB]"
    echo "     -w Warning threshold"
    echo "     -c Critical threshold"
	echo "     -w and -c values in GB"
	exit $STATE_UNKNOWN
}

while getopts "w:c:" opt; do
	case $opt in
	w) WARN=${OPTARG} ;;
	c) CRIT=${OPTARG} ;;
	*) usage ;;
	esac
done


unset message
unset freespace

nb_volumes=0

# On récupère la liste des volumes
volumes=$(gluster volume list 2> /dev/null)

if [[ -z "${volumes// }" ]]; then
  echo "UNKNOWN: No volumes found on this cluster"
  exit 3
fi

for volume in ${volumes}; do
  let $((nb_volumes++))
  unset errors
  unset msg
  freegb=9999999
  nb_online_bricks=0
  # Le nombre de bricks que l'on devrait trouver
  nb_bricks=$(gluster volume info ${volume} | grep "Number of Bricks" | rev |cut -d ' ' -f1 | rev)

  # Itération sur la sortie de status detail pour récupérer les valeurs du
  # runtime
  while read -r line; do
    field=($(echo ${line}))
    case ${field[0]} in
    Brick)
      # Le nom de la brick
      brick=${field[@]:2}
      ;;
    Online)
      # Status de la brick
      online=${field[@]:2}
      if [[ "${online}" == "Y" ]]; then
        let $((nb_online_bricks++))
      else
        errors=("${errors[@]}" "${brick} offline")
      fi
      ;;
    Disk)
      # Espace libre
          key=${field[@]:0:3}
        if [[ "${key}" == "Disk Space Free" ]]; then
              freeunit=${field[@]:4}
              free=${freeunit:0:-2}
              freeconvgb=`echo "($free*1024)" | bc`
              unit=${freeunit#$free}
              if [[ "$unit" == "TB" ]]; then
                  free=$freeconvgb
                  unit="GB"
              fi
              if [[ "$unit" != "GB" ]]; then
                  echo "UNKNOWN : unknown disk space size $freeunit"
                  exit 3
              fi
              free=$(echo "${free} / 1" | bc -q)
              if [[ $free -lt $freegb ]]; then
                  freegb=$free
              fi
          fi
      ;;
    esac
  done < <(gluster volume status ${volume} detail) #while

  if [[ $nb_online_bricks -eq 0 ]]; then
    exit_status="CRITICAL"
    errors=("${errors[@]}" "no bricks found")
  elif [[ $nb_online_bricks -lt $nb_bricks ]]; then
    if [[ ${exit_status} != "CRITICAL" ]]; then
      exit_status="WARNING"
    fi
    errors=("${errors[@]}" "found ${nb_online_bricks} bricks, expected ${nb_bricks}")
  fi

  if [ -n "$CRIT" -a -n "$WARN" ]; then
	if [ $CRIT -ge $WARN ]; then
	  echo "UNKNOWN: critical free space threshold above warning"
	  exit 3
	elif [ $freegb -lt $CRIT ]; then
        errors=("${errors[@]}" "very low free space (${freegb}GB)")
	    exit_status="CRITICAL"
	elif [ $freegb -lt $WARN ]; then
        errors=("${errors[@]}" "low free space (${freegb}GB)")
        if [[ ${exit_status} != "CRITICAL" ]]; then
          exit_status="WARNING"
        fi
	fi
  fi

  if [ -n "$errors" ]; then
    sep="; "
    msg=$(printf "${sep}%s" "${errors[@]}")
    msg=${msg:${#sep}}
    message=("${message[@]}" "-- ${volume}: ${msg}")
  fi
  freespace=("${freespace[@]}" "${volume}: ${freegb}GB")
done #for

if [[ ${exit_status} == "CRITICAL" ]]; then
    echo "CRITICAL: ${message[@]}"
    exit 1
elif [[ ${exit_status} == "WARNING" ]]; then
    echo "WARNING: ${message[@]}"
    exit 2
fi

echo "OK ${nb_volumes} volumes running. Free space: ${freespace[@]}"
exit 0

