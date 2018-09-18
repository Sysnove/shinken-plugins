#!/bin/bash

# Disable STDERR output, comment it while debugging
exec 2> /dev/null

SCRIPT_NAME=`basename $0`

# Nagios return codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

# Nagios final state (OK by default)
NAGIOS_STATE=$STATE_OK

# Nagios final output
NAGIOS_OUTPUT=
NAGIOS_PERF_OUTPUT=

# Get path of requierd utilities
CURL=$(which curl)			   # curl path
#XMLSTARLET=$(which xmlstarlet) # xmlstarlet path

# Command-line variables
O_SOLR_HOST="localhost"  # default solr host
O_SOLR_PORT=8983		 # default solr port
O_TIMEOUT=10			 # default check timeout in seconds
O_SSL=0					 # are we using ssl

# Check that curl is exists
[ -z $CURL ] && {
	echo "Could not find 'curl' utility in the PATH."
	exit $STATE_UNKNOWN
}

# Check that curl is exists
[ -z $XMLSTARLET ] && {
	echo "Could not find 'xmlstarlet' utility in the PATH."
	exit $STATE_UNKNOWN
}

# Usage syntax
USAGE="usage: $SCRIPT_NAME [-H host] [-P <port>] [-T <seconds>] [-h]"

# Print help along with usage
print_help()
{
    echo "$SCRIPT_NAME - Nagios plugin to check Apache Solr"

    echo -e "\n$USAGE\n"

    echo "Parameters description:"
    echo " -H|--host <host>          # Solr host (default is localhost)"
    echo " -S|--ssl <host>           # Same as above, but connect with HTTPS"
    echo " -P|--port <port>          # Solr port number (default is 8983)"
    echo " -T|--timeout              # Solr host connection timeout (used by curl)"
    echo " -h|--help                 # Print this message"
}

# Execute 'curl' command and print it's output
exec_curl() {
	local RESPONSE EXITCODE

	RESPONSE=$(curl --max-time $O_TIMEOUT --fail --silent $@)
	EXITCODE=$?

	echo $RESPONSE
	return $EXITCODE
}

# Print help if requested
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    print_help
    exit $STATE_UNKNOWN
fi

# Parse parameters
while [ $# -gt 0 ]; do
    case "$1" in
        -H|--host) shift
            O_SOLR_HOST=$1
            ;;
        -S|--ssl) shift
            O_SOLR_HOST=$1
            O_SSL=1
            ;;
        -P|--port) shift
            O_SOLR_PORT=$1
            ;;
        -T|--timeout) shift
            O_TIMEOUT=$1
            ;;
        *)  echo "Unknown argument: $1"
            exit $STATE_UNKNOWN
            ;;
    esac
    shift
done

# Check that we can connect to solr host
exec_curl ${URL_PREFIX}${O_SOLR_HOST}:${O_SOLR_PORT}/solr/admin/ping >/dev/null || {
	echo "CRITICAL: host '$O_SOLR_HOST' is not responding."
	exit $STATE_CRITICAL
}

# Print final output and exit
echo "OK: Ping OK"
exit $NAGIOS_OK
