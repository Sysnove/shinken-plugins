#!/bin/sh

last=$(tail -n 1 /var/log/ispconfig/ispconfig.log | cut -d ' ' -f 1)

if [ $? -ne 0 ]; then
    echo "UNKNOWN - Unable to read /var/log/ispconfig/ispconfig.log"
    exit 3
fi

lastdate=$(echo $last | cut -d '-' -f 1)
lasthour=$(echo $last | cut -d '-' -f 2)

lasttimestamp=$(date --date="$(echo $lastdate | cut -d '.' -f 2)/$(echo $lastdate | cut -d '.' -f 1)/$(echo $lastdate | cut -d '.' -f 3) $lasthour" +"%s")

currenttimestamp=$(date +"%s")

delay=$((($currenttimestamp - $lasttimestamp) / 3600))

if [ $delay -ne 0 ]; then
    echo "WARNING - ISPConfig cron is $delay hours late."
    exit 1
fi

if sudo mysql dbispconfig -e "select * from sys_datalog where datalog_id > $(sudo mysql -sN dbispconfig -e 'select updated from server;')"

echo "OK - ISPConfig cron is up to date"
exit 0
