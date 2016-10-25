#!/bin/bash

LOGS=$1

total=$(cat $LOGS | grep "" -c)

e404=$(cat $LOGS | cut -d ' ' -f 9 | grep '404' -c)
e50x=$(cat $LOGS | cut -d ' ' -f 9 | grep '50.' -c)

# :TODO:maethor:161022: if $total > 0
pourcent404=$((($e404 * 100) / $total))
pourcent50x=$((($e50x * 100) / $total))

echo "OK - $total requests, $e404 404 ($pourcent404%), $e50x 50x ($pourcent50x%)"
