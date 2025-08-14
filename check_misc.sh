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
set +e
# shellcheck disable=SC2009
varnish_vcl=$(ps faux | grep varnishd | grep -Eo '\-f .*\.vcl' | head -n 1 | cut -d ' ' -f 2)
if [ -f "$varnish_vcl" ]; then
    if grep -q -E '^ *.probe = {' "$varnish_vcl"; then
        echo "CRITICAL - Probe should be disabled in $varnish_vcl"
        exit 2
    fi
fi
)

(
$NAGIOS_PLUGINS/check_ntp_time -H 0.debian.pool.ntp.org | cut -d '|' -f 1
/usr/bin/sudo /usr/local/nagios/plugins/check_inotify_user_instances.sh | cut -d '|' -f 1
/usr/bin/sudo /usr/local/nagios/plugins/check_cron_log.sh
if [ -f /etc/cron.d/ipinfo ]; then
    /usr/bin/sudo /usr/local/nagios/plugins/check_ipinfo_bl.sh
fi

if ! systemd-detect-virt -q; then
    if $TEST_SENSORS; then
        $NAGIOS_PLUGINS/check_sensors
    fi

    if $TEST_IPMI_SENSORS && [ -f $NAGIOS_PLUGINS/check_ipmi_sensor ] && [ -f /usr/sbin/ipmi-sensors ]; then
        if timeout 5s sudo /usr/sbin/ipmi-sensors > /dev/null 2>&1; then
            cpu_min_freq="$(LC_ALL=C lscpu | grep "min MHz" | awk '{printf "%.0f\n", $NF + 20}')"
	    [ -z "$cpu_min_freq" ] && cpu_min_freq=820
            if [ "$(grep 'cpu MHz' /proc/cpuinfo | awk '{sum+=$NF; nb+=1} END {printf "%.0f\n", sum/nb}')" -lt "$cpu_min_freq" ]; then
                #echo "CRITICAL - CPU is running at 800Mhz. Could be an hardware problem. Please check impi-sensors."
                #exit 2
                timeout 5s $NAGIOS_PLUGINS/check_ipmi_sensor --nosel -xT Entity_Presence,Voltage,Physical_Security,Management_Subsystem_Health | cut -d '|' -f 1
            fi
        fi
    fi
fi


echo "OK - Everything is Awesome"
) | tac # Shinken uses the first line as the main output, so we need to inverse the output
