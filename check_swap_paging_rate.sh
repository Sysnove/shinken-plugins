#!/bin/bash
# Show the rate of swapping (in number of pages) between executions

OK=0
WARNING=1
CRITICAL=2
UNKNOWN=-1
EXITFLAG=$OK

WARN_THRESHOLD=1
CRITICAL_THRESHOLD=100

IN_DATAFILE="/var/tmp/nagios_check_swap_pages_in.dat"
OUT_DATAFILE="/var/tmp/nagios_check_swap_pages_out.dat"
VALID_INTERVAL=600

function usage()
{
    echo "usage: $0 --warn=<pages per second in or out> --critical=<pages per second in or out>"
    echo "Script checks for any swap usage"
}

while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        --warn)
            WARN_THRESHOLD=$VALUE
            ;;
        --critical)
            CRITICAL_THRESHOLD=$VALUE
            ;;
        -h | --help)
            usage
            exit 0;
            ;;
    esac
    shift
done


NOW=`date +%s`
min_valid_ts=$(($NOW - $VALID_INTERVAL))

CURRENT_PAGES_SWAPPED_IN=`vmstat -s | grep 'pages swapped in' | awk '{print $1}'`
CURRENT_PAGES_SWAPPED_OUT=`vmstat -s | grep 'pages swapped out' | awk '{print $1}'`

mkdir -p $(dirname $IN_DATAFILE)
if [ ! -f $IN_DATAFILE ]; then
    echo -e "$NOW\t$CURRENT_PAGES_SWAPPED_IN" > $IN_DATAFILE
    echo "Missing $IN_DATAFILE; creating"
    EXITFLAG=$UNKNOWN
fi
if [ ! -f $OUT_DATAFILE ]; then
    echo -e "$NOW\t$CURRENT_PAGES_SWAPPED_OUT" > $OUT_DATAFILE
    echo "Missing $OUT_DATAFILE; creating"
    EXITFLAG=$UNKNOWN
fi

if [ $EXITFLAG != $OK ]; then
    exit $EXITFLAG
fi

function swap_rate() {
    local file=$1
    local current=$2
    local rate=0
    
    mv $file ${file}.previous
    while read ts swap_count; do
        if [[ $ts -lt $min_valid_ts ]]; then
            continue
        fi
        if [[ $ts -ge $NOW ]]; then
            # we can't use data from the same second
            continue
        fi
        # calculate the rate
        swap_delta=$(($current - $swap_count))
        ts_delta=$(($NOW - $ts))
        rate=`echo "$swap_delta / $ts_delta" | bc`
        echo -e "$ts\t$swap_count" >> $file
    done < ${file}.previous
    echo -e "$NOW\t$current" >> $file
    echo $rate
}

in_rate=`swap_rate $IN_DATAFILE $CURRENT_PAGES_SWAPPED_IN`
out_rate=`swap_rate $OUT_DATAFILE $CURRENT_PAGES_SWAPPED_OUT`

echo "swap in/out is $in_rate/$out_rate per second"
if [[ $in_rate -ge $CRITICAL_THRESHOLD ]] || [[ $out_rate -ge $CRITICAL_THRESHOLD ]]; then
    exit $CRITICAL
fi
if [[ $in_rate -ge $WARN_THRESHOLD ]] || [[ $out_rate -ge $WARN_THRESHOLD ]]; then
    exit $WARNING
fi
exit $OK
