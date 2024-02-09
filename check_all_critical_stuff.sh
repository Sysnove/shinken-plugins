#!/bin/bash

set -e
set -o pipefail

check_tmp_rw(){
    cp /etc/motd /tmp/$$.tmp
    rm /tmp/$$.tmp
    echo "OK - /tmp is writable"
}

(
check_tmp_rw
/usr/lib/nagios/plugins/check_nrpe -H localhost -c check_disk_full

for dbms in mysql pg mongodb redis; do
    if grep -q "command\[check_${dbms}_connection\]" /etc/nagios/nrpe.d/nrpe_local.cfg; then
        /usr/lib/nagios/plugins/check_nrpe -H localhost -c check_${dbms}_connection
    fi
done

for webserver in apache2 nginx; do
    if grep -q "command\[check_${webserver}_status\]" /etc/nagios/nrpe.d/nrpe_local.cfg; then
        /usr/lib/nagios/plugins/check_nrpe -H localhost -c check_${webserver}_status
    fi
done

echo "OK - Everything is Awesome"
) | tac # Shinken uses the first line as the main output, so we need to inverse the output
