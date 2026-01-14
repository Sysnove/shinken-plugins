#!/bin/bash
#
# Important : This scripts checks stuff that should be OK 99.99999% of the time
#

if [ -d /usr/lib/nagios/plugins ]; then
    NAGIOS_PLUGINS=/usr/lib/nagios/plugins
else
    NAGIOS_PLUGINS=/usr/lib64/nagios/plugins
fi

set -e
set -o pipefail


#TEST_GRUB=true
#TEST_RELEASE=true
TEST_IMAP=true
#TEST_NTP=true
#TEST_INOTIFY=true
#TEST_CRON=true
TEST_SENSORS=true
TEST_IPMI_SENSORS=true


while test $# -gt 0
do
    case "$1" in
        --no-imap) TEST_IMAP=false
            ;;
        --no-sensors) TEST_SENSORS=false
            ;;
        --no-ipmi-sensors) TEST_IPMI_SENSORS=false
            ;;
    esac
    shift
done


if [ -f /etc/debian_version ] ; then
    if ! [ -f /boot/grub/grub.cfg ] ; then
        if ! [ "$(jq -r '.host.model' /etc/sysnove.json)" == "container" ]; then
            echo "CRITICAL - /boot/grub/grub.cfg does not exist, please run update-grub2 and grub-install"
            exit 2
        fi
    fi
fi

if lsb_release -d | grep -Eq '(Ubuntu|Debian)'; then
    lsb_release_distrib="$(lsb_release -cs)"
    motd_distrib="$(grep -o 'OS :.*' /etc/motd | grep -o '(.*)' | grep -o '[A-Za-z]*')"

    if [ -n "$motd_distrib" ] && [ "$lsb_release_distrib" != "$motd_distrib" ]; then
        echo "CRITICAL - Host is running on $lsb_release_distrib but /etc/motd contains $motd_distrib, you should run post_upgrade.sh"
        exit 2
    fi
fi

if [ ! -d /etc/.git ] ; then
    echo "CRITICAL - No /etc/.git, etckeeper is not working"
    exit 2
fi

if $TEST_IMAP; then
    if ! $NAGIOS_PLUGINS/check_tcp -H imap.snmail.fr -p 587 -t 1 > /dev/null; then
        echo "CRITICAL - Could not connect to imap.snmail.fr:587"
        exit 2
    fi
fi

(
$NAGIOS_PLUGINS/check_ntp_time -H 0.debian.pool.ntp.org | cut -d '|' -f 1
/usr/local/nagios/plugins/check_shorewall_custom_conf.sh | cut -d '|' -f 1
/usr/bin/sudo /usr/local/nagios/plugins/check_failover_interfaces.sh | cut -d '|' -f 1
/usr/bin/sudo /usr/local/nagios/plugins/check_inotify_user_instances.sh | cut -d '|' -f 1
/usr/bin/sudo /usr/local/nagios/plugins/check_cron_log.sh
#/usr/bin/sudo /usr/local/nagios/plugins/check_ansible_groups.sh
if [ -f /etc/cron.d/ipinfo ]; then
    /usr/bin/sudo /usr/local/nagios/plugins/check_ipinfo_bl.sh
fi
if [ -d /etc/nginx ]; then
    /usr/local/nagios/plugins/check_nginx_config.sh
fi
if [ -f /proc/mdstat ]; then
    /usr/local/nagios/plugins/check_md_nbdisks.sh
fi
if pgrep varnishd >/dev/null; then
    /usr/local/nagios/plugins/check_varnish_vcl.sh
fi

if ! systemd-detect-virt -q; then
    /usr/local/nagios/plugins/check_sensors.sh
    if $TEST_SENSORS; then
        $NAGIOS_PLUGINS/check_sensors
    fi

    if $TEST_IPMI_SENSORS && [ -f $NAGIOS_PLUGINS/check_ipmi_sensor ] && [ -f /usr/sbin/ipmi-sensors ]; then
        /usr/local/nagios/plugins/check_ipmi_sensors.sh
    fi
fi

echo "OK - Everything is Awesome"
) | tac # Shinken uses the first line as the main output, so we need to inverse the output
