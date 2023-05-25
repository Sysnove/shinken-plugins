#!/bin/bash

OKS=()
NOKS=()
PERFDATA=""

(
while read -r line; do
    device=$(echo "$line" | cut -d '_' -f 3 | cut -d ']' -f 1)
    check_command=$(echo "$line" | cut -d '=' -f 2)

    out=$($check_command)
    ret=$?

    if [ $ret -eq 0 ]; then
        OKS+=("$device")
    else
        NOKS+=("$device")
    fi

    if echo "$out" | grep -q '|'; then
        perfdata=$(echo "$out" | cut -d '|' -f 2 | sed "s#=#_$device=#g")
        main=$(echo "$out" | cut -d '|' -f 1)
        PERFDATA="$PERFDATA $perfdata"

        echo "$main"
    else
        echo "$out"
    fi
done < <(grep check_smart /etc/nagios/nrpe.d/nrpe_physical.cfg)

if [ ${#NOKS[@]} -eq 0 ]; then
    echo "OK: [${OKS[*]}] are all clean | $PERFDATA"
    exit 0
elif [ ${#NOKS[@]} -eq 1 ]; then
    echo "${NOKS[*]} is not OK | $PERFDATA"
    exit 1
else
    echo "[${NOKS[*]}] are not OK | $PERFDATA"
    exit 2
fi
) | tac # Shinken uses the first line as the main output, so we need to inverse the output
