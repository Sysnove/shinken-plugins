#!/bin/bash

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

dangerous_files="$(locate --regex '^.*/(web_system.php)$' 2>&1)"
if [ -n "$dangerous_files" ]; then
    critical "$(echo "$dangerous_files" | wc -l) dangerous file(s) has been found : $dangerous_files"
fi

if [ $RET -eq 0 ]; then
    echo "Everything seems OK"
fi

exit $RET
