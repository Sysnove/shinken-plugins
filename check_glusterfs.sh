#!/bin/bash

unset message

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

  # get volume heal status
  heal=0
  for entries in $(sudo gluster volume heal "${volume}" info | awk '/^Number of entries: /{print $4}'); do
    if [ "$entries" -gt 0 ]; then
      let $((heal+=entries))
    fi
  done
  if [ "$heal" -gt 0 ]; then
    exit_status="CRITICAL"
    errors=("${errors[@]}" "$heal unsynched entries")
  fi

  # get brick status
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

  if [ -n "$errors" ]; then
    sep="; "
    msg=$(printf "${sep}%s" "${errors[@]}")
    msg=${msg:${#sep}}
    message=("${message[@]}" "-- ${volume}: ${msg}")
  fi
done #for

if [[ ${exit_status} == "CRITICAL" ]]; then
    echo "CRITICAL: ${message[@]}"
    exit 1
elif [[ ${exit_status} == "WARNING" ]]; then
    echo "WARNING: ${message[@]}"
    exit 2
fi

echo "OK ${nb_volumes} volumes running."
exit 0

