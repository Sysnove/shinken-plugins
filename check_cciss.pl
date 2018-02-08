#!/bin/sh
#
# HP Smart Array Hardware status plugin for Nagios | Written by Simone Rosa
# with HP Array Configuration Utility CLI          |  info [X]
# and  HPE Smart Storage Administrator             | simonerosa
# (hpacucli / hpssacli)                            |   {X} it
#
#
# Description:
#
# This plugin checks hardware status for Smart Array Controllers,
# using the HP Array Configuration Utility CLI / HPE Smart Storage Administrator.
# (Array, controller, cache, battery, etc...)
#
#
# Usage: ./check_cciss [-v] [-p] [-e <number>] [-E <name>] [-b] [-s] [-d]
#
#  -v                   = show status and informations about RAID
#  -p                   = show detail for physical drives
#  -e <number>          = exclude slot number
#  -E <name>            = exclude chassis name
#  -b                   = exclude battery/capacitor/cache status check
#  -s                   = detect controller with HPSA driver (Hewlett Packard Smart Array)
#  -d                   = use for debug (command line mode)
#  -h                   = help information
#  -V                   = version information
#
#
# !!!!!! NOTE: !!!!!!
#
# HP Array Configuration Utility CLI (hpacucli) and
# HPE Smart Storage Administrator (hpssacli) need administrator rights.
#
# Please add this line to /etc/sudoers :
# --------------------------------------------------
# nagios      ALL=NOPASSWD: /usr/sbin/hpacucli, /usr/sbin/hpssacli
#
# !!!!!!! NOTE: !!!!!!
#
# - Please update the hpacucli to the current version (today 9.40) or >8.70
# - If you are using hpssacli (today HPE Smart Storage Administrator CLI 2.40.13.0) change hpssacli permissions:
#     # chmod 555 /usr/sbin/hpssacli  (default are 500 root:root)
#     # chmod 555 /usr/sbin/hpacucli
# - HP Proliant G9 work correctly with "hpssacli". Please NOT install "hpacucli"
# - RHEL7 use "ssacli":
#     # ln -s /usr/sbin/ssacli /usr/sbin/hpssacli
#     # and check /etc/sudoers user (example:   nrpe ALL=NOPASSWD: /usr/sbin/hpacucli, /usr/sbin/hpssacli)
#
# !!!!!!!!!!!!!!!!!!!
#
# Examples:
#
#   ./check_cciss
# ----------------
# RAID OK
#
#   ./check_cciss -v
# -------------------
# RAID OK:  Smart Array 6i in Slot 0 array A logicaldrive 1 (67.8 GB, RAID 1+0, OK)
#           [Controller Status: OK  Cache Status: OK  Battery Status: OK]
#
# RAID CRITICAL - HP Smart Array Failed:  Smart Array 6i in Slot 0 (Embedded) \
#          array A logicaldrive 1 (33.9 GB, RAID 1, Interim Recovery Mode) \
#          physicaldrive 1:0 (port 1:id 0 , Parallel SCSI, --- GB, Failed)
#
# RAID WARNING - HP Smart Array Rebuilding:  Smart Array 6i in Slot 0 (Embedded) \
#          array A logicaldrive 1 (33.9 GB, RAID 1, Recovering, 26% complete) \
#          physicaldrive 1:0 (port 1:id 0 , Parallel SCSI, 36.4 GB, Rebuilding)
#
# ./check_cciss -v -p
# --------------------
# RAID OK:  Smart Array 6i in Slot 0 (Embedded) array A logicaldrive 1 (33.9 GB, RAID 1, OK)
#           physicaldrive 2:0 (port 2:id 0 , Parallel SCSI, 36.4 GB, OK)
#           physicaldrive 2:1 (port 2:id 1 , Parallel SCSI, 36.4 GB, OK)
#           physicaldrive 1:5 (port 1:id 5 , Parallel SCSI, 72.8 GB, OK, spare)
#           [Controller Status: OK Cache Status: OK Battery/Capacitor Status: OK]
#
# RAID CRITICAL - HP Smart Array Failed:  Smart Array 6i in Slot 0 (Embedded) \
#          array A logicaldrive 1 (33.9 GB, RAID 1, Interim Recovery Mode) \
#          physicaldrive 1:0 (port 1:id 0 , Parallel SCSI, --- GB, Failed) \
#          physicaldrive 1:1 (port 1:id 1 , Parallel SCSI, 36.4 GB, OK)
#
# RAID WARNING - HP Smart Array Rebuilding:  Smart Array 6i in Slot 0 (Embedded) \
#          array A logicaldrive 1 (33.9 GB, RAID 1, Recovering, 26% complete) \
#          physicaldrive 1:0 (port 1:id 0 , Parallel SCSI, 36.4 GB, Rebuilding) \
#          physicaldrive 1:1 (port 1:id 1 , Parallel SCSI, 36.4 GB, OK)
#
# ./check_cciss -v -b
# ----------------
#
# RAID OK:  Smart Array 6i in Slot 0 (Embedded) array A logicaldrive 1 (33.9 GB, RAID 1, OK) [Controller Status: OK]
#
#  [insted of]
# RAID CRITICAL - HP Smart Array Failed:  Smart Array 6i in Slot 0 (Embedded) \
#                 Controller Status: OK Cache Status: Temporarily Disabled \
#                 Battery/Capacitor Status: Failed (Replace Batteries/Capacitors)
#
#
# ChangeLog:
#
# 2017/04/28 (1.15)
#          - Added debug for hpacucli/hpssacli section
#          - Added note for hpssacli (today HPE Smart Storage Administrator CLI)
#             # chmod 555 /usr/sbin/hpssacli  (default are 500 root:root)
#             # chmod 555 /usr/sbin/hpacucli
#          - Added note for RHEL7 (ssacli and sudoers user) 
#          - Script tested with HP Proliant G9
#
# 2017/02/25 (1.14)
#          - Updated headers for versions from 1.8 to 1.13
#
# 2017/01/23 (1.13)
#          - Support hpssacli in addition to hpacucli
#          - Added cli flag '-b' to exclude battery/capacitor/cache status check
#
# 2013/11/20 (1.12)
#          - Auto-detect the HPSA driver (tested with DL360/380 G6 with Ubuntu 12.04 LTS)
#
# 2012/07/16 (1.11)
#          - Fixed little NRPE description output issue (only in one physicaldrive critical output)
#
# 2012/04/04 (1.10)
#          - Critical states have priority over warning states
#          - Fixed check physical drives for predicted failures without show detail (-p)
#          - Fixed check physical drives for predicted failures in "chassis name" mode
#
# 2012/03/06 (1.9)
#          - Increased debug verbosity
#          - Added arguments to detect controller with HPSA driver (Hewlett Packard Smart Array) (-s)
#          - Recognize required firmware upgrades
#          - Don't confuse messages about a new fimrware with a chassis-error
#          - Check physical drives for predicted failures
#          - Added arguments to show detail for physical drives (-p)
#          - Check the state of the cache (a dead battery will turn the cache off)
#            (thanks to Casper Gielen and Kim Hagen)
#
# 2008/10/06 (1.8)
#          - Added support for chassis name (example MSA500)
#          - Added arguments to exclude slot number (-e <n>) and chassis name (-E <name>)
#          - Added "Recovering" status reporting
#          - Updated for hpacucli 8.10 version
#
# 2008/07/12 (1.7)
#          - Changed command argument support to use getopts and dropped the now unnecessary -N and -c options
#            (thanks to Reed Loden)
#
# 2008/07/06 (1.6)
#          - Added support for multiple arrays
#            (thanks to Reed Loden)
#
# 2008/05/30 (1.5)
#          - Added support for checking cache and battery status; added autodetection of slot number; corrected typo
#            (thanks to Reed Loden)
#
# 2006/01/25 (1.4)
#          - Changed "Rebuilding" grep with "Rebuild" for capture "Ready for Rebuild" status
#            (thanks to Loris A.)
#
# 2005/12/24 (1.3)
#          - Added STATE_UNKNOWN when hpacucli command failed (if sudo exit with error)
#            (thanks to Tim Hughes)
#
# 2005/10/10 (1.2)
#          - Now it's compatible with "Compaq Smart Array"
#            (suggested by Hans Engelen)
#
# 2005/10/07 (1.1)
#          - Debug messages
#
# 2005/10/06 (1.0)
#          - First production version
# 

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

PROGNAME=`basename $0`
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`
REVISION=`echo '$Revision: 1.15 $' | sed -e 's/[^0-9.]//g'`
HPSA="0"
DEBUG="0"
VERBOSE="0"
HPPROC="/proc/driver/cciss/cciss"
HPSCSIPROC="/proc/scsi/scsi"
COMPAQPROC="/proc/driver/cpqarray/ida"
hpacucli="/usr/sbin/hpacucli"
hpssacli="/usr/sbin/hpssacli"

. /usr/lib/nagios/plugins/utils.sh

print_usage() {
        echo ""
        echo "Usage: $PROGNAME [-v] [-p] [-e <number>] [-E <name>] [-b] [-s] [-d]"
        echo "Usage: $PROGNAME [-h]"
        echo "Usage: $PROGNAME [-V]"
        echo ""
        echo "  -v                   = show status and informations about RAID"
        echo "  -p                   = show detail for physical drives"
        echo "  -e <number>          = exclude slot number"
        echo "  -E <name>            = exclude chassis name"
        echo "  -b                   = exclude battery/capacitor/cache status check"
        echo "  -s                   = detect controller with HPSA driver (Hewlett Packard Smart Array)"
        echo "  -d                   = use for debug (command line mode)"
        echo "  -h                   = help information"
        echo "  -V                   = version information"
        echo ""
        echo " === NOTE: ==="
        echo ""
	echo " HP Array Configuration Utility CLI (hpacucli) and"
	echo " HPE Smart Storage Administrator (hpssacli) need administrator rights."
	echo ""
        echo " Please add this line to /etc/sudoers"
        echo " --------------------------------------------------"
        echo " nagios      ALL=NOPASSWD: /usr/sbin/hpacucli, /usr/sbin/hpssacli"
        echo ""
        echo " - Please update the hpacucli to the current version (today 9.40) or >8.70"
        echo " - If you are using hpssacli (today HPE Smart Storage Administrator CLI 2.40.13.0) change hpssacli permissions:"
        echo "    # chmod 555 /usr/sbin/hpssacli  (default are 500 root:root)"
        echo "    # chmod 555 /usr/sbin/hpacucli"
        echo " - HP Proliant G9 work correctly with \"hpssacli\" Please NOT install \"hpacucli\""
        echo " - RHEL7 use \"ssacli\":"
        echo "     # ln -s /usr/sbin/ssacli /usr/sbin/hpssacli"
        echo "     # and check /etc/sudoers user (example:   nrpe ALL=NOPASSWD: /usr/sbin/hpacucli, /usr/sbin/hpssacli)"
	echo ""
	echo " ============="
}

print_help() {
        print_revision $PROGNAME $REVISION
        echo ""
        print_usage
        echo ""
        echo "This plugin checks hardware status for Smart Array Controllers,"
	echo "using the HP Array Configuration Utility CLI / HPE Smart Storage Administrator."
        echo ""
        support
        exit 0
}

while getopts "N:cvpbsde:E:Vh" options
do
    case $options in
      N)  ;;
      c)  ;;
      v)  VERBOSE=1;;
      p)  PHYSICAL_DRIVE=1;;
      s)  HPSA=1;;
      d)  DEBUG=1;;
      e)  EXCLUDE_SLOT=1
          excludeslot="$OPTARG";;
      E)  EXCLUDE_CH=1
          excludech="$OPTARG";;
      b)  EXCLUDE_BATTERY=1;;
      V)  print_revision $PROGNAME $REVISION
          exit 0;;
      h)  print_help
          exit 0;;
      \?) print_usage
          exit 0;;
      *)  print_usage
          exit 0;;
  esac
done

# Use HPSA driver (Hewlett Packard Smart Array)
if [ "$HPSA" = "1" -o -d /sys/bus/pci/drivers/hpsa ]; then
        COMPAQPROC="/proc/scsi/scsi"
fi

# Check if "HP Smart Array" is present
raid=`cat $HPPROC* 2>&1`
status=$?
if [ "$DEBUG" = "1" ]; then
        echo "### Check if \"HP Smart Array\" ($HPPROC) is present >>>\n"${raid}"\n"
fi
if test ${status} -eq 1; then
        raid=`cat $COMPAQPROC* 2>&1`
        status=$?
        if [ "$DEBUG" = "1" ]; then
                echo "### Check if \"HP Smart Array\" ($COMPAQPROC) is present >>>\n"${raid}"\n"
        fi
        if test ${status} -eq 1; then
                echo "RAID UNKNOWN - HP Smart Array not found"
                exit $STATE_UNKNOWN
        fi
fi

# Check if "HP Array Utility CLI" is present
if [ "$DEBUG" = "1" ]; then
        echo "### Check if \"hpacucli\" is present >>>\n"
fi
if [ ! -x $hpacucli ]; then
	if [ "$DEBUG" = "1" ]; then
        	echo "### \"hpacucli\" is NOT present >>>\n"
		echo "### Check if \"hpssacli\" is present >>>\n"
	fi
        if [ -x $hpssacli ]; then
		if [ "$DEBUG" = "1" ]; then
		        echo "### \"hpssacli\" is present >>>\n"
		fi
                hpacucli='/usr/sbin/hpssacli'
        else
                echo "ERROR: hpacucli or hpssacli tools should be installed and check sudoers/permissions (see the notes above)"
                exit $STATE_UNKNOWN
        fi
fi

# Check if "HP Controller" work correctly
check=`sudo -u root $hpacucli controller all show status 2>&1`
status=$?
if [ "$DEBUG" = "1" ]; then
        echo "### Check if \"HP Controller\" work correctly >>>\n"${check}"\n"
fi
if test ${status} -ne 0; then
        echo "RAID UNKNOWN - $hpacucli did not execute properly : "${check}
        exit $STATE_UNKNOWN
fi

# Get "Slot" & exclude slot needed
if [ "$EXCLUDE_SLOT" = "1" ]; then
        slots=`echo ${check} | egrep -o "Slot \w" | awk '{print $NF}' | grep -v "$excludeslot"`
else
        slots=`echo ${check} | egrep -o "Slot \w" | awk '{print $NF}'`
fi
if [ "$DEBUG" = "1" ]; then
        echo "### Get \"Slot\" & exclude slot not needed >>>\n"${slots}"\n"
fi
for slot in $slots
do
        # Get "logicaldrive" for slot
        check2b=`sudo -u root $hpacucli controller slot=$slot logicaldrive all show 2>&1`
        status=$?
        if test ${status} -ne 0; then
                echo "RAID UNKNOWN - $hpacucli did not execute properly : "${check2b}
                exit $STATE_UNKNOWN
        fi
        check2="$check2$check2b"
        if [ "$DEBUG" = "1" ]; then
                echo "### Get \"logicaldrive\" for slot >>>\n"${check2b}"\n"
        fi

        # Get "physicaldrive" for slot
        if [ "$PHYSICAL_DRIVE" = "1" -o "$DEBUG" = "1" ]; then
                check2b=`sudo -u root $hpacucli controller slot=$slot physicaldrive all show | sed -e 's/\?/\-/g' 2>&1 | grep "physicaldrive"`
        else
                check2b=`sudo -u root $hpacucli controller slot=$slot physicaldrive all show | sed -e 's/\?/\-/g' 2>&1 | grep "physicaldrive" | grep "\(Failure\|Failed\|Rebuilding\)"`
        fi
        status=$?
        if [ "$PHYSICAL_DRIVE" = "1" -o "$DEBUG" = "1" ]; then
                if test ${status} -ne 0; then
                        echo "RAID UNKNOWN - $hpacucli did not execute properly : "${check2b}
                        exit $STATE_UNKNOWN
                fi
        fi
        check2="$check2$check2b"
        if [ "$DEBUG" = "1" ]; then
                echo "### Get \"physicaldrive\" for slot >>>\n"${check2b}"\n"
        fi
done

# Get "Chassis" & exclude chassis not needed
if [ "$EXCLUDE_CH" = "1" ]; then
        chassisnames=`echo ${check} | grep -v "in a scenario of" | egrep -o "in \w+" | egrep -v "Slot" | awk '{print $NF}' | grep -v "$excludech"`
else
        chassisnames=`echo ${check} | grep -v "in a scenario of" | egrep -o "in \w+" | egrep -v "Slot" | awk '{print $NF}'`
fi
if [ "$DEBUG" = "1" ]; then
        echo "### Get \"Chassis\" & exclude chassis not needed >>>\n"${chassisnames}"\n"
fi
for chassisname in $chassisnames
do
        # Get "logicaldrive" for chassisname
        check2b=`sudo -u root $hpacucli controller chassisname="$chassisname" logicaldrive all show 2>&1`
        status=$?
        if test ${status} -ne 0; then
                echo "RAID UNKNOWN - $hpacucli did not execute properly : "${check2b}
                exit $STATE_UNKNOWN
        fi
        check2="$check2$check2b"
        if [ "$DEBUG" = "1" ]; then
                echo "### Get \"logicaldrive\" for chassisname >>>\n"${check2b}"\n"
        fi

        # Get "physicaldrive" for chassisname
        if [ "$PHYSICAL_DRIVE" = "1" -o "$DEBUG" = "1" ]; then
                check2b=`sudo -u root $hpacucli controller chassisname="$chassisname" physicaldrive all show | sed -e 's/\?/\-/g' 2>&1 | grep "physicaldrive"`
        else
                check2b=`sudo -u root $hpacucli controller chassisname="$chassisname" physicaldrive all show | sed -e 's/\?/\-/g' 2>&1 | grep "physicaldrive" | grep "\(Failure\|Failed\|Rebuilding\)"`
        fi
        status=$?
        if [ "$PHYSICAL_DRIVE" = "1" -o "$DEBUG" = "1" ]; then
                if test ${status} -ne 0; then
                        echo "RAID UNKNOWN - $hpacucli did not execute properly : "${check2b}
                        exit $STATE_UNKNOWN
                fi
        fi
        check2="$check2$check2b"
        if [ "$DEBUG" = "1" ]; then
                echo "### Get \"physicaldrive\" for chassisname >>>\n"${check2b}"\n"
        fi
done

# Check STATUS
if [ "$DEBUG" = "1" ]; then
       echo "### Check STATUS >>>"
fi

# Omit battery/capacitor/cache status check if requested
if [ "$EXCLUDE_BATTERY" = "1" ]; then
       check=`echo "$check" | grep -v 'Battery/Capacitor Status: Failed (Replace Batteries/Capacitors)'`
       check=`echo "$check" | grep -v 'Cache Status: Temporarily Disabled'`
fi

if echo ${check} | egrep Failed >/dev/null; then
        echo "RAID CRITICAL - HP Smart Array Failed: "${check} | egrep Failed
        exit $STATE_CRITICAL
elif echo ${check} | egrep Disabled >/dev/null; then
        echo "RAID CRITICAL - HP Smart Array Problem: "${check} | egrep Disabled
        exit $STATE_CRITICAL
elif echo ${check2} | egrep Failed >/dev/null; then
        echo "RAID CRITICAL - HP Smart Array Failed: "${check2} | egrep Failed
        exit $STATE_CRITICAL
elif echo ${check2} | egrep Failure >/dev/null; then
        echo "RAID WARNING - Component Failure: "${check2} | egrep Failure
        exit $STATE_WARNING
elif echo ${check2} | egrep Rebuild >/dev/null; then
        echo "RAID WARNING - HP Smart Array Rebuilding: "${check2} | egrep Rebuild
        exit $STATE_WARNING
elif echo ${check2} | egrep Recover >/dev/null; then
        echo "RAID WARNING - HP Smart Array Recovering: "${check2} | egrep Recover
        exit $STATE_WARNING
elif echo ${check} | egrep "Cache Status: Temporarily Disabled" >/dev/null; then
        echo "RAID WARNING - HP Smart Array Cache Disabled: "${check}
        exit $STATE_WARNING
elif echo ${check} | egrep FIRMWARE >/dev/null; then
        echo "RAID WARNING - "${check}
        exit $STATE_WARNING
else
        if [ "$DEBUG" = "1" -o "$VERBOSE" = "1" ]; then
                check3=`echo "${check}" | egrep Status`
                check3=`echo ${check3}`
                echo "RAID OK: "${check2}" ["${check3}"]"
        else
                echo "RAID OK"
        fi
        exit $STATE_OK
fi

exit $STATE_UNKNOWN
