#!/bin/bash

if [ -d /usr/lib/nagios/plugins ]; then
    NAGIOS_PLUGINS=/usr/lib/nagios/plugins
else
    NAGIOS_PLUGINS=/usr/lib64/nagios/plugins
fi

set -o pipefail

check_tmp_rw(){
    cp /etc/motd /tmp/$$.tmp
    rm /tmp/$$.tmp
    echo "OK - /tmp is writable"
}

(
# Because check_disk hangs when NFS/SSHFS/CIFS mount point are stale
# https://github.com/monitoring-plugins/monitoring-plugins/issues/1975
# We timeout after 2s and we simply ignore this check if check_disk times out
# TODO Remove when bug is fixed
timeout 2 $NAGIOS_PLUGINS/check_nrpe -4 -H localhost -c check_disk_full | sed 's/|.*//g'
ret="$?"
if [ "$ret" -gt 0 ] && [ "$ret" != 124 ]; then
    exit $ret
fi

set -e
check_tmp_rw

for dbms in mysql pg mongodb redis; do
    if grep -q "command\[check_${dbms}_connection\]" /etc/nagios/nrpe.d/nrpe_local.cfg; then
        $NAGIOS_PLUGINS/check_nrpe -4 -H localhost -c check_${dbms}_connection | sed 's/|.*//g'
    fi
done

if [ -f /etc/apache2/apache2.conf ] || [ -f /etc/nginx/nginx.conf ] || [ -f /etc/haproxy/haproxy.cfg ]; then
    # Sometime we can disable 80 so we need to check both 80 & 443
    /usr/lib/nagios/plugins/check_tcp -H localhost -p 80 || /usr/lib/nagios/plugins/check_tcp -H localhost -p 443 | sed 's/|.*//g'
    # check_http 
    #/usr/lib/nagios/plugins/check_http -H localhost | sed 's/|.*//g'
fi

# Do not work well
#for webserver in apache2 nginx; do
#    if grep -q "command\[check_${webserver}_status\]" /etc/nagios/nrpe.d/nrpe_local.cfg; then
#        $NAGIOS_PLUGINS/check_nrpe -4 -H localhost -c check_${webserver}_status | sed 's/|.*//g'
#    fi
#done

echo "OK - Everything is Awesome"
) | tac # Shinken uses the first line as the main output, so we need to inverse the output
