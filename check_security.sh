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

# :COMMENT:maethor:20210126: I expect this will be noisy
# shellcheck disable=SC2016
if grep -q -E '\:\$1\$' /etc/shadow; then
    warning "md5 passwords found in /etc/shadow"
fi

# shellcheck disable=SC2013
for user in $(awk -F':' '/sysnove/{print $4}' /etc/group | sed "s/,/ /g"); do
    if [ -n "$(find "/home/$user" -name "id_(rsa|dsa|ecdsa|ed25519)")" ]; then
        warning "private SSH key found in /home/$user"
    fi

    if grep -qr  'PRIVATE KEY' "/home/$user/.ssh"; then
        warning "private SSH key found in /home/$user/.ssh"
    fi
done

if [ -n "$(find /tmp -perm -4000 2>/dev/null)" ]; then
    critical "setuid binaries found in /tmp"
fi


#if grep -v '^root:x:0:' /etc/passwd | grep -q 'x:0:'; then
#    critical "Found non-root user with uid=0 in /etc/passwd"
#fi

check_user_home () {
    username=$1
    uid=$2
    home=$3

    # Users should owned their home
    if [ "$(stat -c "%U" "$home")" != "$username" ]; then 
        critical "$home is not owned by $username"
    fi

    # Home should not be group writable
    if stat -c "%a" "$home" | grep -q '.[267].'; then
        critical "$username home directory is group writable."
    fi

    # Home should not be other writable
    if stat -c "%a" "$home" | grep -q '..[267]'; then
        critical "$username home directory is other writable."
    fi

    # :TODO:maethor:20210127: Améliorer ces listes (gérer des répertoires : .bin, .config…)
    # Files that should not be readable by group or other
    for f in .netrc .rhosts .gnupg/secring.gpg .gnupg/random_seed .pgp/secring.pgp .shosts .ssh/identity .ssh/id_dsa .ssh/id_ecdsa .ssh/id_rsa .ssh/id_ed25519 .zhistory .google_authenticator; do
        if [ -f "$home/$f" ] && [ ! -L "$home/$f" ]; then
            if ! stat -c "%a" "$home/$f" | grep -q '.00'; then
                critical "$home/$f is readable or writable by group or other."
            fi
        fi
    done

    # Files that should not be writable by group or other
    for f in .bashrc .bash_profile .bash_login .bash_logout .cshrc .emacs .exrc .forward .fvwmrc .inputrc .kshrc .zlogin .zpreztorc .zprofile .zshenv .zshrc .vimrc .tmux.conf .gitconfig .login .logout .nexrc .profile .screenrc .ssh .ssh/config .ssh/authorized_keys .ssh/authorized_keys2 .ssh/environment .ssh/known_hosts .ssh/rc .tcshrc .twmrc .xsession .xinitrc .Xdefaults .Xauthority; do
        if [ -f "$home/$f" ] && [ ! -L "$home/$f" ]; then
            if stat -c "%a" "$home/$f" | grep -E -q '(.[267].|..[267])'; then
                critical "$home/$f is writable by group or other."
            fi
        fi
    done

}

check_user_home root 0 /root

# shellcheck disable=SC2002
cat /etc/passwd | while IFS= read -r line; do
    username=$(echo "$line" | cut -d ':' -f 1)
    uid=$(echo "$line" | cut -d ':' -f 3)
    home=$(echo "$line" | cut -d ':' -f 6)

    if [ "$uid" -eq 0 ] && [ "$username" != "root" ]; then
        critical "$username uid = 0"
    fi

    # uid > 5000 = ispconfig web user
    if [ "$uid" -ge 1000 ] && [ "$uid" -lt 5000 ] && [ "$username" != "nobody" ]; then
        check_user_home "$username" "$uid" "$home"
    fi
done



ROOT_PATH="$(sudo -Hiu root env | grep PATH | cut -d '=' -f 2)"

# :COMMENT:maethor:20210126: I expect this will not work everywhere, but we'll see
EXPECTED_ROOT_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
if [ "$ROOT_PATH" != "$EXPECTED_ROOT_PATH" ]; then
    critical "Wrong root PATH"
fi

for dir in ${ROOT_PATH//:/ }; do
    # On Debian, /usr/local is writable by staff group.
    if [[ "$dir" == /usr/local* ]]; then
        if stat -c "%a" "$dir" | grep -E -q '..[267]$'; then
            critical "$dir is in root PATH and is writable by other."
        fi
    else
        if stat -c "%a" "$dir" | grep -E -q '(.[267].|..[267])$'; then
            critical "$dir is in root PATH and is writable by group or other."
        fi
    fi
done

exit $RET
