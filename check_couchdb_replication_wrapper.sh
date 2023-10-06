#!/bin/bash

# Manages couchdb 1 and couchdb 2.

couchdb_version=$(curl -s http://localhost:5984/ | jq -r '.version')

if [ -z "$couchdb_version" ]; then
	echo "CRITICAL - Could not retrieve CouchDB version."
	exit 2
fi

if [[ "$couchdb_version" = 1.* ]]; then
	/usr/local/nagios/plugins/check_couchdb_replications.py -r "$1"
	ret=$?
	echo "Couchdb $couchdb_version"
	exit $ret
else
	/usr/local/nagios/plugins/check_couchdb2_replications.sh -H localhost -d
	ret=$?
	echo "Couchdb $couchdb_version"
	exit $ret
fi
