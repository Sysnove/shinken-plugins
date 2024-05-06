#!/bin/bash

CHECK_WEB=true
CHECK_DBS=true

for arg in "$@"; do
    if [ "$arg" == '--no-web' ]; then
        CHECK_WEB=false
    elif [ "$arg" == '--no-dbs' ]; then
        CHECK_DBS=false
    fi
done

RET=0 # OK

critical () {
    echo "SECURITY CRITICAL : $1"
    RET=2
}

warning () {
    echo "SECURITY WARNING : $1"
    [ $RET -eq 0 ] && RET=1
}


# shellcheck disable=SC2013
for user in $(awk -F':' '/^sysnove:/{print $4}' /etc/group | sed "s/,/ /g"); do
    if [ -n "$(find "/home/$user" -name "id_(rsa|dsa|ecdsa|ed25519)")" ]; then
        warning "private SSH key found in /home/$user"
    fi

    if [ -d "/home/$user/.ssh" ] && grep -qr  'PRIVATE KEY' "/home/$user/.ssh"; then
        warning "private SSH key found in /home/$user/.ssh"
    fi
done

if [ -n "$(find /tmp -perm -4000 2>/dev/null)" ]; then
    critical "setuid binaries found in /tmp"
fi


check_user_home () {
    username=$1
    uid=$2
    home=$3

    if [ -d "$home" ] && [ "$home" != "/" ]; then
        if [[ "$home" != /srv* ]]; then
            # Users should owned their home
            if [ "$(stat -c "%U" "$home")" != "$username" ]; then 
                critical "$home is not owned by $username"
            fi

            # Home should not be group writable
            if stat -c "%a" "$home" | grep -q '.[267].'; then
                critical "$username home directory ($home) is group writable."
            fi

            # Home should not be other writable
            if stat -c "%a" "$home" | grep -q '..[267]'; then
                critical "$username home directory ($home) is other writable."
            fi
        fi

        # :TODO:maethor:20210127: Améliorer ces listes (gérer des répertoires : .bin, .config…)
        # Files that should not be readable by group or other
        for f in .netrc .rhosts .gnupg/secring.gpg .gnupg/random_seed .pgp/secring.pgp .shosts .ssh/identity .ssh/id_dsa .ssh/id_ecdsa .ssh/id_rsa .ssh/id_ed25519 .zhistory .google_authenticator; do
            if [ -f "$home/$f" ] && [ ! -L "$home/$f" ]; then
                if [ "$(stat -c "%G" "$home/$f")" = "$username" ]; then
                    check='..0'
                else
                    check='.00'
                fi
                if ! stat -c "%a" "$home/$f" | grep -q "$check"; then
                    critical "$home/$f is readable or writable by group or other."
                fi
            fi
        done

        # Files that should not be writable by group or other
        for f in .bashrc .bash_profile .bash_login .bash_logout .cshrc .emacs .exrc .forward .fvwmrc .inputrc .kshrc .zlogin .zpreztorc .zprofile .zshenv .zshrc .vimrc .tmux.conf .gitconfig .login .logout .nexrc .profile .screenrc .ssh .ssh/config .ssh/authorized_keys .ssh/authorized_keys2 .ssh/environment .ssh/known_hosts .ssh/rc .tcshrc .twmrc .xsession .xinitrc .Xdefaults .Xauthority; do
            if [ -f "$home/$f" ] && [ ! -L "$home/$f" ]; then
                if [ "$(stat -c "%G" "$home/$f")" = "$username" ]; then
                    check='..[267]'
                else
                    check='(.[267].|..[267])'
                fi
                if stat -c "%a" "$home/$f" | grep -E -q "$check"; then
                    critical "$home/$f is writable by group or other."
                fi
            fi
        done
    fi

}

check_user_home root 0 /root


while IFS=: read -ra line; do
    username=${line[0]}
    uid=${line[2]}
    home=${line[5]}

    # Ignore ISPConfig shell users
    if [ -n "$username" ] && [ "$username" != "ispconfig" ] && [[ "$home" != /var/www/clients/* ]]; then
        if [ "$uid" -eq 0 ] && [ "$username" != "root" ]; then
            critical "$username uid = 0"
        fi

        if [ "$uid" -ge 1000 ] && [ "$username" != "nobody" ]; then
            check_user_home "$username" "$uid" "$home"
        fi

        if grep -q "^$username:\$1\\$" /etc/shadow; then
            warning "$username password is stored in md5 in /etc/shadow"
        fi
    fi
done < /etc/passwd


ROOT_PATH="$(sudo -Hiu root env | grep '^PATH=' | cut -d '=' -f 2)"

# :COMMENT:maethor:20210209: Too much exceptions to apply everywhere
if [[ $(hostname) =~ ^(infra|sysnove)- ]]; then
    if [ "$ROOT_PATH" != "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" ]; then
        critical "Wrong root PATH: $ROOT_PATH"
    fi
fi


for dir in ${ROOT_PATH//:/ }; do
    # On Debian, /usr/local is writable by staff group.
    if [[ "$dir" =~ ^/usr/local/(bin|sbin) ]] ||  [[ "$dir" == /usr/local/rvm/* ]]; then
        if stat -c "%a" "$dir" | grep -E -q '..[267]$'; then
            critical "$dir is in root PATH and is writable by other."
        fi
    else
        realdir="$(readlink -f "$dir")"
        if [ ! -d "$realdir" ]; then
            if [ "$realdir" != '/snap/bin' ]; then
                critical "$dir is in root PATH and does not exist."
            fi
        elif stat -c "%a" "$realdir" | grep -E -q '(.[267].|..[267])$'; then
            critical "$dir is in root PATH and is writable by group or other."
        fi
    fi
done

# Too slow for big servers :/
#dangerous_files="$(locate --regex '^.*/(web_system.php)$' 2>&1)"
#if [ -n "$dangerous_files" ]; then
#    critical "$(echo "$dangerous_files" | wc -l) dangerous file(s) has been found : $dangerous_files"
#fi

if [ -e /usr/bin/apt-mark ]; then
    if ! apt_hold=$(/usr/local/nagios/plugins/check_apt_hold.sh); then
        critical "$apt_hold"
    fi
fi

if $CHECK_DBS; then
    if grep -q "command\[check_mysql_connection\]" /etc/nagios/nrpe.d/nrpe_local.cfg; then
        for user in $(sudo mysql -se 'select User from mysql.user;' | grep -Ev '^(enove|mariadb\.sys|mysql)$'); do
            if sudo -u nagios mysql -u "$user" --password="$user" -e 'show databases' > /dev/null 2>&1; then
                critical "MySQL $user's password is $user"
            fi
        done
    fi

    if grep -q "command\[check_pg_connection\]" /etc/nagios/nrpe.d/nrpe_local.cfg; then
        for user in $(sudo -u postgres psql --csv -t -c '\du;' | cut -d ',' -f 1 | grep -Ev '^(postgres|repmgr|sysnove_monitoring|ofbiz)$'); do
            if PGPASSWORD="$user" psql -U "$user" -h localhost -c '\l' > /dev/null 2>&1; then
                critical "PG $user's password is $user"
            fi
        done
    fi
fi

if [ $RET -eq 0 ]; then
    if $CHECK_WEB; then
        /usr/local/nagios/plugins/check_websites_security.sh
        web_security_ret="$?"
        if [ "$web_security_ret" -eq 3 ]; then
            RET=3
        elif [ "$web_security_ret" -eq 2 ]; then
            RET=2
        elif [ "$web_security_ret" -eq 1 ] && [ "$RET" -eq 0 ]; then
            RET=1
        fi
    else
        echo "Everything seems OK"
    fi
fi

exit $RET
