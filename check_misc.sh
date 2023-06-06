#!/bin/bash

if [ -d /usr/lib/nagios/plugins ]; then
    NAGIOS_PLUGINS=/usr/lib/nagios/plugins
else
    NAGIOS_PLUGINS=/usr/lib64/nagios/plugins
fi

set -e
set -o pipefail

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

(
$NAGIOS_PLUGINS/check_ntp_time -H 0.debian.pool.ntp.org | cut -d '|' -f 1
/usr/bin/sudo /usr/local/nagios/plugins/check_inotify_user_instances.sh | cut -d '|' -f 1
/usr/bin/sudo /usr/local/nagios/plugins/check_cron_log.sh

if ! systemd-detect-virt -q; then
    $NAGIOS_PLUGINS/check_sensors
fi

echo "OK - Everything is Awesome"
) | tac # Shinken uses the first line as the main output, so we need to inverse the output
