#!/usr/bin/env bash

#
# Description :
#
# This plugin checks all services are running in a given docker stack.
#
# CopyLeft 2020 Guillaume Subiron <guillaume@sysnove.fr>
#
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the http://www.wtfpl.net/ file for more details.
# 

if [ "$#" -ne 1 ] ; then
    echo "Usage: $0 STACK_NAME"
    exit 3
fi

STACK="$1"

if ! out=$(docker stack ps "$STACK" --format='{{.Name}} {{.CurrentState}}') ; then
    echo "UNKNOWN: Failed to run docker stack ps $STACK"
    exit 3
fi

down=$(echo "$out" | grep -cv " Running ")
running=$(echo "$out" | grep -c " Running ")
total=$(echo "$out" | wc -l)

if [ "$down" -gt 0 ] ; then
	echo "CRITICAL: $down services over $total not running in stack $STACK"
	exit 2
else
	echo "OK: $running/$total services running in stack $STACK"
	exit 0
fi
