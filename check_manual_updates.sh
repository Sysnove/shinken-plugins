#!/bin/bash

apps=""

if [ -f /etc/debian_version ]; then
    if apt-cache policy nginx | grep -q 'http://nginx.org'; then
        nginx_installed=$(aptitude versions nginx | grep '^i' | awk '{print $2}')
        if [ -n "$nginx_installed" ] ; then
            apps="$apps nginx"

            nginx_installed_major=$(echo "$nginx_installed" | cut -f1,2 -d'.')

            nginx_latest=$(aptitude versions nginx | awk '{print $2}' | grep "^$nginx_installed_major" | tail -n 1)

            if [ -n "$nginx_latest" ] && [[ "$nginx_latest" > "$nginx_installed" ]]; then
                echo "WARNING : Nginx $nginx_installed is installed, but $nginx_latest is available."
                exit 1
            fi
        fi
    fi
fi

if [ -f /usr/local/ispconfig/server/lib/config.inc.php ]; then
    apps="$apps ispconfig"

    ispconfig_installed=$(php -r "require_once '/usr/local/ispconfig/server/lib/config.inc.php'; print(ISPC_APP_VERSION);")
    if ispconfig_latest=$(curl -s https://www.ispconfig.org/downloads/ispconfig3_version.txt); then
        if [[ "$ispconfig_latest" > "$ispconfig_installed" ]]; then
            echo "WARNING : ISPConfig $ispconfig_installed is installed, but $ispconfig_latest is available."
            exit 1
        fi
    else
        echo "UNKNOWN : Unable to retrieve ISPConfig latest version."
        exit 3
    fi
fi

gitea_exe=$(pgrep -a gitea | cut -d ' ' -f 2)
if [ -f "$gitea_exe" ]; then
    apps="$apps gitea"

    gitea_installed=$($gitea_exe -v | awk '{print $3}')
    gitea_latest=$(curl -sL https://dl.gitea.io/gitea/version.json | jq -r '.latest.version')

    if [[ "$gitea_latest" > "$gitea_installed" ]]; then
        echo "WARNING : Gitea $gitea_installed is installed, but $gitea_latest is available."
        exit 1
    fi
fi

gogs_exe=$(pgrep -a gogs | cut -d ' ' -f 2)
if [ -f "$gogs_exe" ]; then
    echo "WARNING : Gogs found on $gogs_exe. Please upgrade to gitea."
    exit 1
fi

if [ -f /srv/.nextcloud/version.php ]; then
    apps="$apps nextcloud"

    nextcloud_installed=$(php -r "require_once '/srv/.nextcloud/version.php'; print(\$OC_VersionString);")
    php_version=$(php -v | head -1 | awk '{print $2}' | sed 's/\./x/g')
    nextcloud_call_updater=$(curl -s -A "Nextcloud Updater" https://updates.nextcloud.com/updater_server/?version="$(echo $nextcloud_installed | sed 's/\./x/g')"x1xxxstablexx2022-04-21T15:41:38+00:00%203d4015ae4dc079d1a2be0d3a573edef20264d701x"$php_version")
    nextcloud_latest=$(echo "$nextcloud_call_updater" | grep "<version>" | sed 's/..version.//g' | awk -F '.' '{print $1, ".", $2, ".", $3}')

    if [[ "$nextcloud_latest" > "$nextcloud_installed" ]]; then
        echo "WARNING : Nextcloud $nextcloud_installed is installed, but $nextcloud_latest is available."
        exit 1
    fi
fi

if [ -f /srv/.snappymail/data/VERSION ]; then
    apps="$apps snappymail"

    snappymail_installed="v$(cat /srv/.snappymail/data/VERSION)"
    snappymail_latest=$(curl https://api.github.com/repos/the-djmaze/snappymail/releases/latest -s | jq .name -r)

    if [[ "$snappymail_latest" > "$snappymail_installed" ]]; then
        echo "WARNING : Snappymail $snappymail_installed is installed, but $snappymail_latest is available."
        exit 1
    fi
fi

if repmgr_installed=$(sudo -u postgres repmgr --version 2>&1); then
    repmgr_running=$(sudo -u postgres psql -A -t -d repmgr -c "select extversion from pg_extension where extname='repmgr';")
    if [ -n "$repmgr_running" ]; then
        repmgr_installed=$(echo "$repmgr_installed" | cut -d ' ' -f 2 | cut -d '.' -f 1-2)
        if [ "$repmgr_running" != "$repmgr_installed" ]; then
            echo "WARNING : Repmgr $repmgr_running is running, but $repmgr_installed is installed."
            exit 1
        fi
    fi
fi

if [ -n "$apps" ]; then
    echo "OK : Everything is up to date ($apps)"
else
    echo "OK : No manual updated app detected"
fi
