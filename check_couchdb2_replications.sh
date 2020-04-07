#!/bin/bash
################################################################################
# Script:       check_couchdb_replication.sh                                   #
# Author:       Claudio Kuenzler www.claudiokuenzler.com                       #
# Purpose:      Monitor CouchDB replication                                    #
# Licence:      GPLv2                                                          #
# Licence :     GNU General Public Licence (GPL) http://www.gnu.org/           #
# This program is free software; you can redistribute it and/or                #
# modify it under the terms of the GNU General Public License                  #
# as published by the Free Software Foundation; either version 2               #
# of the License, or (at your option) any later version.                       #
#                                                                              #
# This program is distributed in the hope that it will be useful,              #
# but WITHOUT ANY WARRANTY; without even the implied warranty of               #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                #
#                                                                              #
# GNU General Public License for more details.                                 #
#                                                                              #
# You should have received a copy of the GNU General Public License            #
# along with this program; if not, write to the Free Software                  #
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA                #
# 02110-1301, USA.                                                             #
#                                                                              #
# History:                                                                     #
# 20180105: Created plugin                                                     #
# 20180108: Added -d detection                                                 #
# 20180108: Handle connection problems properly                                #
# 20180326: Input sanitation (either -d or -r are required)                    #
# 20180326: Avoid confusion about wrong credentials (issue 4)                  #
# 20180326: Add possibility to check all replications at once (-r ALL)         #
# 20180326: Handle authentication error "You are not a server admin."          #
################################################################################
#Variables and defaults
STATE_OK=0              # define the exit code if status is OK
STATE_WARNING=1         # define the exit code if status is Warning
STATE_CRITICAL=2        # define the exit code if status is Critical
STATE_UNKNOWN=3         # define the exit code if status is Unknown
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin # Set path
port=5984
protocol=http
################################################################################
#Functions
help () {
echo -e "$0  (c) 2018-$(date +%Y) Claudio Kuenzler (published under GPL licence)

Usage: ./check_couchdb_replication.sh -H MyCouchDBHost [-P port] [-S] [-u user] [-p pass] (-r replication|-d)

Options:

   * -H Hostname or ip address of CouchDB Host (or Cluster IP)
     -P Port (defaults to 5984)
     -S Use https
     -u Username if authentication is required
     -p Password if authentication is required
  ** -r Replication ID to monitor (doc_id)
  ** -d Dynamically detect and list all available replications
     -h Help!

*-H is mandatory for all ways of running the script
**-r is mandatory to check a defined replication (doc_id) 
**-d is mandatory if no replication check (-r) is set

Requirements: curl, jshon, tr"
exit $STATE_UNKNOWN;
}

authlogic () {
if [[ -z $user ]] && [[ -z $pass ]]; then echo "COUCHDB REPLICATION UNKNOWN - Authentication required but missing username and password"; exit $STATE_UNKNOWN
elif [[ -n $user ]] && [[ -z $pass ]]; then echo "COUCHDB REPLICATION UNKNOWN - Authentication required but missing password"; exit $STATE_UNKNOWN
elif [[ -n $pass ]] && [[ -z $user ]]; then echo "COUCHDB REPLICATION UNKNOWN - Missing username"; exit $STATE_UNKNOWN
fi
}
################################################################################
# Check requirements
for cmd in curl jshon tr awk; do
 if ! `which ${cmd} 1>/dev/null`; then
   echo "UNKNOWN: ${cmd} does not exist, please check if command exists and PATH is correct"
   exit ${STATE_UNKNOWN}
 fi
done
################################################################################
# Check for people who need help - aren't we all nice ;-)
if [ "${1}" = "--help" -o "${#}" = "0" ]; then help; exit $STATE_UNKNOWN; fi
################################################################################
# Get user-given variables
while getopts "H:P:Su:p:r:d" Input;
do
  case ${Input} in
  H)      host=${OPTARG};;
  P)      port=${OPTARG};;
  S)      protocol=https;;
  u)      user=${OPTARG};;
  p)      pass=${OPTARG};;
  r)      repid=${OPTARG};;
  d)      detect=1;;
  *)      help;;
  esac
done

# Check for mandatory opts
if [ -z ${host} ]; then help; exit $STATE_UNKNOWN; fi
if [ -z ${detect} ] && [ -z ${repid} ]; then help; exit $STATE_UNKNOWN; fi
################################################################################
# If -d (detection) is used, present list of replications
if [[ ${detect} -eq 1 ]]; then
  if [[ -n $user && -n $pass ]]
    then authlogic; cdburl="${protocol}://${user}:${pass}@${host}:${port}/_active_tasks"
    else cdburl="${protocol}://${host}:${port}/_active_tasks"
  fi
  cdbresp=$(curl -k -s $cdburl)

  if [[ -n $(echo $cdbresp | grep -i "Name or password is incorrect") ]]; then
    echo "COUCHDB REPLICATION CRITICAL - Unable to authenticate user $user"
    exit $STATE_CRITICAL
  elif [[ -n $(echo $cdbresp | grep -i "You are not a server admin") ]]; then
    echo "COUCHDB REPLICATION CRITICAL - You are not a server admin"
    exit $STATE_CRITICAL
  elif [[ -z $cdbresp ]]; then
    echo "COUCHDB REPLICATION CRITICAL - Unable to connect to CouchDB on ${protocol}://${host}:${port}"
    exit $STATE_CRITICAL
  fi

  replist=$(echo $cdbresp | jshon -a -e "doc_id" | tr '\n' ' ')
  if [[ -n $replist ]]; then
    echo "COUCHDB AVAILABLE REPLICATIONS: $replist"
    exit $STATE_OK
  else
    echo "COUCHDB AVAILABLE REPLICATIONS: no replications found"
    exit $STATE_WARNING 
  fi
fi

# Do the replication check for all replications
if [[ "${repid}" == "ALL" ]]
then 
  if [[ -n $user && -n $pass ]]
    then authlogic; cdburl="${protocol}://${user}:${pass}@${host}:${port}/_scheduler/docs/_replicator"
    else cdburl="${protocol}://${host}:${port}/_scheduler/docs/_replicator"
  fi
  cdbresp=$(curl -k -s $cdburl)

  if [[ -n $(echo $cdbresp | grep -i "Name or password is incorrect") ]]; then
    echo "COUCHDB REPLICATION CRITICAL - Unable to authenticate user $user"
    exit $STATE_CRITICAL
  elif [[ -n $(echo $cdbresp | grep -i "You are not a server admin") ]]; then
    echo "COUCHDB REPLICATION CRITICAL - You are not a server admin"
    exit $STATE_CRITICAL
  fi

  # Count failed replications
  failedrepls=$(echo "$cdbresp"| grep database | grep -v '"state":"running"')
  failedcount=$(echo "$failedrepls" | wc -l)

  if [[ ${failedcount} -gt 0 ]] && [[ ${failedrepls} =~ "database" ]]
  then 
    failedinfo=$(echo "$failedrepls" | awk -F',' '{print $2" "$7" "$8}' | tr "\n" ",")
    #echo "COUCHDB REPLICATION CRITICAL - ${failedcount} replications not running" $cdbresp"| grep database | grep -v '"state":"running"' | awk -F',' '{print $2" "$7" "$8}' | tr "\n" ","
    echo "COUCHDB REPLICATION CRITICAL - ${failedcount} replications not running ($failedinfo)" 
    exit $STATE_CRITICAL
  else 
    echo "COUCHDB REPLICATION OK - All replications running"; exit $STATE_OK
  fi

else
  # Do the replication check for a single replication
  if [[ -n $user && -n $pass ]]
    then authlogic; cdburl="${protocol}://${user}:${pass}@${host}:${port}/_scheduler/docs/_replicator/${repid}"
    else cdburl="${protocol}://${host}:${port}/_scheduler/docs/_replicator/${repid}"
  fi
  cdbresp=$(curl -k -s $cdburl)
  
  if [[ -n $(echo $cdbresp | grep -i "Name or password is incorrect") ]]; then
    echo "COUCHDB REPLICATION CRITICAL - Unable to authenticate user $user"
    exit $STATE_CRITICAL
  elif [[ -n $(echo $cdbresp | grep -i "You are not a server admin") ]]; then
    echo "COUCHDB REPLICATION CRITICAL - You are not a server admin"
    exit $STATE_CRITICAL
  elif [[ -n $(echo $cdbresp | grep -i missing) ]]; then
    echo "COUCHDB REPLICATION CRITICAL - Replication for $repid not found"
    exit $STATE_CRITICAL
  elif [[ -z $cdbresp ]]; then
    echo "COUCHDB REPLICATION CRITICAL - Unable to connect to CouchDB on ${protocol}://${host}:${port}"
    exit $STATE_CRITICAL
  fi
  
  repstatus=$(echo $cdbresp | jshon -e state)
  
  if [[ "$repstatus" == '"running"' ]]; then
    echo "COUCHDB REPLICATION OK - Replication $repid is $repstatus"
    exit $STATE_OK
  else 
    echo "COUCHDB REPLICATION CRITICAL - Replication $repid is $repstatus"
    exit $STATE_CRITICAL
  fi
fi
