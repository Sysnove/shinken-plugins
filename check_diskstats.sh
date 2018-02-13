#!/bin/bash

WARNING="80"
CRITICAL="100"

E_OK=0
E_WARNING=1
E_CRITICAL=2
E_UNKNOWN=3

show_help() {
	echo "$0 [-w pct_business] [-c pct_business] | -h"
	echo
	echo "This plug-in is used to be alerted when maximum hard drive io utilization is reached."
	echo
	echo "  -w/c PCT_BUSINESS  Percentage of disk business."
	echo
	echo " example: $0 -w 80 -c 90"
}

# process args
while [ ! -z "$1" ]; do 
	case $1 in
		-w)	shift; WARNING=$1 ;;
		-c)	shift; CRITICAL=$1 ;;
		-h)	show_help; exit 1 ;;
	esac
	shift
done

# generate HISTFILE filename
HISTFILE=/var/tmp/check_diskstat

# kernel handles sectors by 512bytes
# http://www.mjmwired.net/kernel/Documentation/block/stat.txt
SECTORBYTESIZE=512

sanitize() {
	if [ -z "$WARNING" ]; then
		echo "Need warning threshold"
		exit $E_UNKNOWN
	fi
	if [ -z "$CRITICAL" ]; then
		echo "Need critical threshold"
		exit $E_UNKNOWN
	fi
}

readdiskstat() {
	if [ ! -f "/proc/diskstats" ]; then
		return $E_UNKNOWN
	fi

	cat /proc/diskstats
}

readhistdiskstat() {
	[ -f $HISTFILE ] && cat $HISTFILE
}

# check args
sanitize


NEWDISKSTAT="$(readdiskstat)"
if [ $? -eq $E_UNKNOWN ]; then
	echo "Cannot read disk stats, check /proc/diskstats"
	exit $E_UNKNOWN
fi

if [ ! -f $HISTFILE ]; then
	echo "$NEWDISKSTAT" >$HISTFILE
	echo "UNKNOWN - Initial buffer creation..." 
	exit $E_UNKNOWN
fi

OLDDISKSTAT=$(readhistdiskstat)
if [ $? -ne 0 ]; then
	echo "Cannot read histfile $HISTFILE..."
	exit $E_UNKNOWN
fi
OLDDISKSTAT_EPOCH=$(date -r $HISTFILE +%s)
NEWDISKSTAT_EPOCH=$(date +%s)

let "TIME = $NEWDISKSTAT_EPOCH - $OLDDISKSTAT_EPOCH"

PERFDATA=""
OUTPUT="Disk business is OK"
EXITCODE=$E_OK

echo "$NEWDISKSTAT" >$HISTFILE
# now we have old and current stat; 
# let compare it for each device
for DEVICE in `ls /sys/block`; do
	if [ -L /sys/block/$DEVICE/device ]; then
        OLD_READ=$(echo "$OLDDISKSTAT" | grep " $DEVICE " | awk '{print $4}')
        NEW_READ=$(echo "$NEWDISKSTAT" | grep " $DEVICE " | awk '{print $4}')
        OLD_WRITE=$(echo "$OLDDISKSTAT" | grep " $DEVICE " | awk '{print $8}')
        NEW_WRITE=$(echo "$NEWDISKSTAT" | grep " $DEVICE " | awk '{print $8}')

        OLD_TIME_READING=$(echo "$OLDDISKSTAT" | grep " $DEVICE " | awk '{print $7}')
        NEW_TIME_READING=$(echo "$NEWDISKSTAT" | grep " $DEVICE " | awk '{print $7}')
        OLD_TIME_WRITING=$(echo "$OLDDISKSTAT" | grep " $DEVICE " | awk '{print $11}')
        NEW_TIME_WRITING=$(echo "$NEWDISKSTAT" | grep " $DEVICE " | awk '{print $11}')

        OLD_SECTORS_READ=$(echo "$OLDDISKSTAT" | grep " $DEVICE " | awk '{print $6}')
        NEW_SECTORS_READ=$(echo "$NEWDISKSTAT" | grep " $DEVICE " | awk '{print $6}')
        OLD_SECTORS_WRITTEN=$(echo "$OLDDISKSTAT" | grep " $DEVICE " | awk '{print $10}')
        NEW_SECTORS_WRITTEN=$(echo "$NEWDISKSTAT" | grep " $DEVICE " | awk '{print $10}')

        let "SECTORS_READ = $NEW_SECTORS_READ - $OLD_SECTORS_READ"
        let "SECTORS_WRITE = $NEW_SECTORS_WRITTEN - $OLD_SECTORS_WRITTEN"

        let "TIME_READING = $NEW_TIME_READING - $OLD_TIME_READING"
        let "TIME_WRITING = $NEW_TIME_WRITING - $OLD_TIME_WRITING"

        let "PCT_BUSY = 100 * ($TIME_READING + $TIME_WRITING) / ($TIME * 1000)"
        let "PCT_BUSY_READING = 100 * ($TIME_READING) / ($TIME * 1000)"
        let "PCT_BUSY_WRITING = 100 * ($TIME_WRITING) / ($TIME * 1000)"

        let "READS_PER_SEC=($NEW_READ - $OLD_READ) / $TIME"
        let "WRITES_PER_SEC=($NEW_READ - $OLD_READ) / $TIME"
        
        let "BYTES_READ_PER_SEC = $SECTORS_READ * $SECTORBYTESIZE / $TIME"
        let "BYTES_WRITTEN_PER_SEC = $SECTORS_WRITE * $SECTORBYTESIZE / $TIME"
        let "KBYTES_READ_PER_SEC = $BYTES_READ_PER_SEC / 1024"
        let "KBYTES_WRITTEN_PER_SEC = $BYTES_WRITTEN_PER_SEC / 1024"

        PERFDATA="$PERFDATA ${DEVICE}_pct_reading=$PCT_BUSY_READING% ${DEVICE}_pct_writing=$PCT_BUSY_WRITING% ${DEVICE}_read=${BYTES_READ_PER_SEC}bps ${DEVICE}_write=${BYTES_WRITTEN_PER_SEC}bps ${DEVICE}_rps=${READS_PER_SEC}r/s ${DEVICE}_wps=${WRITES_PER_SEC}w/s"

        DATA="$DATA$DEVICE=$PCT_BUSY% "

        # check TPS
        if [ $PCT_BUSY -gt $WARNING ]; then
            if [ $PCT_BUSY -gt $CRITICAL ]; then
                OUTPUT="CRITICAL : $DEVICE I/O business is $PCT_BUSY% (>$CRITICAL%)"
                EXITCODE=$E_CRITICAL
            elif [ $EXITCODE -lt $E_WARNING ]; then
                OUTPUT="WARNING : $DEVICE I/O business is $PCT_BUSY% (>$WARNING%)"
                EXITCODE=$E_WARNING
            fi
        fi
	fi
done

echo "$OUTPUT ($DATA) | $PERFDATA"

exit $EXITCODE
