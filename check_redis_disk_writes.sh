#!/bin/bash

E_OK=0
E_WARNING=1
#E_CRITICAL=2
E_UNKNOWN=3

THRESHOLD=$1
[ -z "$THRESHOLD" ] && THRESHOLD=5000

pids=$(pidof redis-server)
if [ -z "$pids" ]; then
    echo "UNKNOWN - Redis is not running"
    exit $E_UNKNOWN
fi

LAST_RUN_FILE=/var/tmp/nagios/check_redis_disk_writes_last_run

NAGIOS_USER=${SUDO_USER:-$(whoami)}
if ! [ -d "$(dirname "$LAST_RUN_FILE")" ]; then
    install -g "$NAGIOS_USER" -o "$NAGIOS_USER" -m 750 -d "$(dirname "$LAST_RUN_FILE")"
fi

if [ -f "$LAST_RUN_FILE" ] && [ ! -O "$LAST_RUN_FILE" ]; then
    echo "UNKNOWN: $LAST_RUN_FILE is not owned by $USER"
    exit $E_UNKNOWN
fi

old_write_bytes=-1
last_check=-1
# shellcheck disable=SC1090
source "$LAST_RUN_FILE"

if [ "$(date -r /var/lib/redis +%s)" -lt $last_check ]; then
    echo "UNKNOWN - Redis has not persist since last run. Please run the check later."
    exit $E_UNKNOWN
fi

now=$(date +%s)

write_bytes=0
for pid in $pids; do
    write_bytes=$((write_bytes + $(grep '^write_bytes' "/proc/$pid/io" | awk '{print $2}')))
done

echo "
old_write_bytes=$write_bytes
last_check=$now
" > "$LAST_RUN_FILE"

if [ $last_check -eq -1 ]; then
    echo "UNKNOWN - First run, please run the check again."
    exit $E_UNKNOWN
fi

if [ "$write_bytes" -lt $old_write_bytes ] ; then
    echo "UNKNOWN - Counters have been reset since last run, please run the check again."
    exit $E_UNKNOWN
fi

delta=$((write_bytes - old_write_bytes))
period=$((now - last_check))

rate=$(bc <<< "scale=0; $delta / 1024 / $period")

output="Redis was writing at ${rate} KBps on disks over the last ${period}s | redis_writes=${rate}Bps;$THRESHOLD;;0;;"

if [ "$rate" -gt "$THRESHOLD" ]; then
    echo "WARNING - $output"
    exit $E_WARNING
else
    echo "OK - $output"
    exit $E_OK
fi
