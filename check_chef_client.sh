#!/bin/bash

CHEF_CONFIG="/etc/chef/client.rb"

status=$(knife status -c $CHEF_CONFIG)

if [ $? != 0 ] ; then
    echo "UNKNOWN : \"knife status\" returned an error."
    exit 3
fi

node_name=$(cat $CHEF_CONFIG | grep 'node_name' | awk {'print $2'} | sed 's/"//g')

late=$(echo "$status" | grep "$node_name" | awk {'print $1 $2'})

if [ -z "$late" ] ; then
    echo "CRITICAL: $node_name doesn't seem to be listed by \"knife status\"."
    exit 2
fi

if echo "$late" | grep -q hour ; then
    echo "WARNING : Chef client is late: last run $late ago."
    exit 1
fi

echo "OK : Chef client last run $late ago."
exit 0

