#!/bin/bash

if [ -d /usr/lib/nagios/plugins ]; then
    NAGIOS_PLUGINS=/usr/lib/nagios/plugins
else
    NAGIOS_PLUGINS=/usr/lib64/nagios/plugins
fi

set -e
set -o pipefail

check_tmp_rw(){
    cp /etc/motd /tmp/$$.tmp
    rm /tmp/$$.tmp
    echo "OK - /tmp is writable"
}

(
check_tmp_rw
$NAGIOS_PLUGINS/check_nrpe -4 -H localhost -c check_disk_full

for dbms in mysql pg mongodb redis; do
    if grep -q "command\[check_${dbms}_connection\]" /etc/nagios/nrpe.d/nrpe_local.cfg; then
        $NAGIOS_PLUGINS/check_nrpe -4 -H localhost -c check_${dbms}_connection
    fi
done

if [ -f /etc/apache2/apache2.conf ] || [ -f /etc/nginx/nginx.conf ] || [ -f /etc/haproxy/haproxy.cfg ]; then
    # Sometime we can disable 80 so we need to check both 80 & 443
    /usr/lib/nagios/plugins/check_tcp -H localhost -p 80 || /usr/lib/nagios/plugins/check_tcp -H localhost -p 443
    # check_http 
    #/usr/lib/nagios/plugins/check_http -H localhost
fi

# Do not work well
#for webserver in apache2 nginx; do
#    if grep -q "command\[check_${webserver}_status\]" /etc/nagios/nrpe.d/nrpe_local.cfg; then
#        $NAGIOS_PLUGINS/check_nrpe -4 -H localhost -c check_${webserver}_status
#    fi
#done

echo "OK - Everything is Awesome"
) | tac # Shinken uses the first line as the main output, so we need to inverse the output
