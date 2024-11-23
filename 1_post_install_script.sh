#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2154

current_dir="$(pwd)"
unypkg_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
unypkg_root_dir="$(cd -- "$unypkg_script_dir"/.. &>/dev/null && pwd)"

cd "$unypkg_root_dir" || exit

#############################################################################################
### Start of script

mkdir -p /var/mail
groupadd -g 32 postfix &&
    groupadd -g 33 postdrop &&
    useradd -c "Postfix Daemon User" -d /var/spool/postfix -g postfix \
        -s /bin/false -u 32 postfix &&
    chown -v postfix:postfix /var/mail

if [ ! -f /etc/uny/postfix/main.cf ]; then
    install -v -dm 755 -o postfix -g postfix /etc/uny/postfix
    cp -a etc/uny/postfix/* /etc/uny/postfix/
    sbin/postfix -c /etc/uny/postfix set-permissions
fi

#############################################################################################
### End of script

cd "$current_dir" || exit