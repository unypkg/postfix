#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2154

set -vx

######################################################################################################################
### Setup Build System and GitHub

##apt install -y autopoint

wget -qO- uny.nu/pkg | bash -s buildsys

### Installing build dependencies
unyp install lmdb libnsl cyrus-sasl icu openssl pcre2

#pip3_bin=(/uny/pkg/python/*/bin/pip3)
#"${pip3_bin[0]}" install --upgrade pip
#"${pip3_bin[0]}" install docutils pygments

### Getting Variables from files
UNY_AUTO_PAT="$(cat UNY_AUTO_PAT)"
export UNY_AUTO_PAT
GH_TOKEN="$(cat GH_TOKEN)"
export GH_TOKEN

source /uny/git/unypkg/fn
uny_auto_github_conf

######################################################################################################################
### Timestamp & Download

uny_build_date

mkdir -pv /uny/sources
cd /uny/sources || exit

pkgname="postfix"
pkggit="https://github.com/vdukhovni/postfix.git refs/tags/*"
gitdepth="--depth=1"

### Get version info from git remote
# shellcheck disable=SC2086
latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "v[0-9]+\.[0-9.]+$" | tail --lines=1)"
latest_ver="$(echo "$latest_head" | grep -o "v[0-9.].*" | sed "s|v||")"
latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

version_details

# Release package no matter what:
echo "newer" >release-"$pkgname"

git_clone_source_repo

#cd "$pkg_git_repo_dir" || exit
#./autogen.sh
#cd /uny/sources || exit

mv -v postfix postfix_source
mv -v postfix_source/postfix postfix

archiving_source

######################################################################################################################
### Build

# unyc - run commands in uny's chroot environment
# shellcheck disable=SC2154
unyc <<"UNYEOF"
set -vx
source /uny/git/unypkg/fn

pkgname="postfix"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths

####################################################
### Start of individual build script

#unset LD_RUN_PATH
unset LD_LIBRARY_PATH

groupadd -g 32 postfix &&
    groupadd -g 33 postdrop &&
    useradd -c "Postfix Daemon User" -d /var/spool/postfix -g postfix \
        -s /bin/false -u 32 postfix &&
    chown -v postfix:postfix /var/mail

sed -i 's/.\x08//g' README_FILES/*

sed 's#(uname -r) 2>/dev/null#\(uname -r | grep -o "^[0-9.]\*") 2>/dev/null#' -i makedefs
sed '/	CCARGS="$CCARGS -DNO_EAI"/a SYSLIBS="\$SYSLIBS $icu_ldflags"' -i makedefs
sed '#CCARGS="\$CCARGS -DNO_EAI"#CCARGS="\$CCARGS \$icu_cppflags"#' -i makedefs
sed 's#CCARGS="\$CCARGS -DNO_EAI"'\'' -DDEF_SMTPUTF8_ENABLE=\\"no\\"'\''#CCARGS="\$CCARGS $(pkgconf --cflags icu-uc icu-i18n)" SYSLIBS="\$SYSLIBS $(pkgconf --libs icu-uc icu-i18n)"#' -i makedefs
sed "s|-DNO_EAI||g" -i makedefs

CCARGS="-DNO_NIS -DNO_DB"
AUXLIBS=""

cyrus_dir=(/uny/pkg/cyrus-sasl/*)
CCARGS="$CCARGS -DUSE_SASL_AUTH -DUSE_CYRUS_SASL -I${cyrus_dir[0]}/include/sasl"
AUXLIBS="$AUXLIBS -L${cyrus_dir[0]}/lib -lsasl2"

CCARGS="$CCARGS -DHAS_LMDB"
AUXLIBS="$AUXLIBS -llmdb"

openssl_dir=(/uny/pkg/openssl/*)
CCARGS="$CCARGS -DUSE_TLS -I${openssl_dir[0]}/include/openssl"
AUXLIBS="$AUXLIBS -L${openssl_dir[0]}/lib -lssl -lcrypto"

icu_dir=(/uny/pkg/icu/*)
CCARGS="$CCARGS -I${icu_dir[0]}/include"
AUXLIBS="$AUXLIBS -L${icu_dir[0]}/lib -licui18n -licuuc -licudata"

pcre2_dir=(/uny/pkg/pcre2/*)
CCARGS="$CCARGS -DHAS_PCRE=2 -I${pcre2_dir[0]}/include"
AUXLIBS_PCRE=$(pcre2-config --libs8)

export install_root=/uny/pkg/"$pkgname"/"$pkgver"

make CCARGS="$CCARGS" AUXLIBS="$AUXLIBS" SYSLIBS="$SYSLIBS" AUXLIBS_PCRE="$AUXLIBS_PCRE" \
    SHLIB_RPATH="-Wl,--enable-new-dtags -Wl,--dynamic-linker=$(grep -o "^.*glibc/[^:]*" /uny/paths/lib)/ld-linux-x86-64.so.2 -Wl,-rpath=/uny/pkg/"$pkgname"/"$pkgver"/lib:$LIBRARY_PATH" \
    shared=yes pie=yes dynamicmaps=yes \
    config_directory=/etc/uny/postfix meta_directory=/etc/uny/postfix \
    daemon_directory="$install_root"/lib/postfix \
    command_directory="$install_root"/sbin \
    mailq_path="$install_root"/bin/mailq \
    newaliases_path="$install_root"/bin/newaliases \
    sendmail_path="$install_root"/sbin/sendmail \
    shlib_directory="$install_root"/lib \
    manpage_directory="$install_root"/share/man \
    makefiles &&
    make

mkdir -p "$install_root"/lib
cp -a lib/* "$install_root"/lib/

sed "s#^PATH=.*#PATH=$PATH#" -i postfix-install
sh postfix-install -non-interactive #-package
    #config_directory=/etc/uny/postfix meta_directory=/etc/uny/postfix \
    #daemon_directory="$install_root"/lib/postfix \
    #command_directory="$install_root"/sbin \
    #mailq_path="$install_root"/bin/mailq \
    #newaliases_path="$install_root"/bin/newaliases \
    #sendmail_path="$install_root"/sbin/sendmail \
    #shlib_directory="$install_root"/lib \
    #manpage_directory="$install_root"/share/man

tee "$install_root"/etc/postfix.service >/dev/null <<EOF
[Unit]
Description=Postfix Mail Transport Agent
After=network.target

[Service]
CapabilityBoundingSet=~ CAP_NET_ADMIN CAP_SYS_ADMIN CAP_SYS_BOOT CAP_SYS_MODULE
ExecReload=${install_root}/sbin/postfix reload
ExecStart=${install_root}/sbin/postfix start
ExecStop=${install_root}/sbin/postfix stop
PIDFile=/var/spool/postfix/pid/master.pid
PrivateDevices=true
PrivateTmp=true
ProtectSystem=true
Restart=always
Type=forking

[Install]
Alias=postfix.service
WantedBy=multi-user.target
EOF

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end
UNYEOF

######################################################################################################################
### Packaging

package_unypkg
