#!/bin/bash - 
#===============================================================================
#
#          FILE: obfuscated_sshd.sh
# 
#         USAGE: ./obfuscated_sshd.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Tony lEE <lüftreich@gmail.com>
#  ORGANIZATION: 
#       CREATED: 08/20/2014 20:35
#      REVISION:  ---
#===============================================================================
#
#                     (c) Copyright LUFT.Ltd 2014 - 2144, All Rights Reserved
#
# Revision History:
#                       Modification     Tracking
# Author (core ID)          Date          Number     Description of Changes
# -------------------   ------------    ----------   ----------------------
#
# Lüftreich             **/**/2014        2.0        ****
# Lüftreich             **/**/2014        1.0        ****
#===============================================================================

# set -x              # Print commands and their arguments as they are executed
set -o nounset                              # Treat unset variables as an error

cur_cmd=`readlink -f $0`
cur_dir=${cur_cmd%/*}

cd $cur_dir
. ./init_func.sh

usage()
{
    cat << _EOF

    Usage: sh $0 {start|stop|restart}

_EOF

}

gen_public_key()
{
    probe_root

    local set_dir=/home/$gfw_user/.ssh
    local prev_umask=`umask`
    comment_str='CHN-Anti-GFW'
    umask 0077
    mkdir -p $set_dir
    cd $set_dir || exit
    echo "$*" | grep -q '\-\-force' && rm -f authorized_keys; sync
    test -f authorized_keys || {
        ssh-keygen -f ${key_file} -t rsa -C "$comment_str"
        cat ${key_file}.pub >> authorized_keys
        cd ..
        chown ${gfw_user}:${gfw_user} -R .ssh
        cd -
        apt-get -y install putty-tools
        puttygen ${key_file} -C $comment_str -O private -o ${win32_key_file}
        tar cvfz $key_tar_file ${key_file} ${key_file}.pub ${win32_key_file} && \
            rm ${key_file} ${key_file}.pub ${win32_key_file} -f
        echo 'PRIVATE KEY IS OK !'
        umask $prev_umask
    }
}

mk_win32_cmd()
{
    ## For Win32
    mkdir -p $cur_dir/win32
    cd $cur_dir/win32 || exit

    tar xf $key_tar_file ${win32_key_file} || exit $?
    wget -c http://www.mrhinkydink.com/utmods/063/plonk.exe
    cat > dli.cmd << _EOF
@echo off
title Proxy_g_f_w_l_x_l
plonk "$host_addr" -C -N -D $forward_port -ssh -2 -P $srv_port -Z $key_code -l $gfw_user -i ${win32_key_file} -v

_EOF
    unix2dos dli.cmd
    7z a -p'1234' $pkg_dir/anti_gfwin32.7z *
    echo 'Password: 1234'
    sync
}

start_sshd()
{
    DEBUG=${DEBUG:='0'}
    probe_root

    out_iface='eth0'
    vps_iface='venet0:0' ## YZM
    ifconfig $vps_iface 2>/dev/null && out_iface=${vps_iface}

    pre_install
    cd $cur_dir || exit
    mkdir -p /var/temp
    mkdir -p /var/empty
    [ -f $OBF_HOST_KEY ] || ssh-keygen -f $OBF_HOST_KEY -t rsa

    cat > $OBF_SSHD_CONFIG << _EOF

Protocol 2
Port 2201
ObfuscatedPort $srv_port
ObfuscateKeyword $key_code

# AllowGroups $gfw_user
AllowUsers  $gfw_user
PermitRootLogin no
# AuthorizedKeysFile	%h/.ssh/authorized_keys

HostKey $OBF_HOST_KEY

RSAAuthentication yes
PubkeyAuthentication yes
# PermitEmptyPasswords no

Subsystem       sftp    /usr/libexec/sftp-server

_EOF

    add_initd

    # Add valid user
    id $gfw_user >/dev/null || {
        useradd -m -b /home -k /dev/null -s /usr/sbin/nologin $gfw_user
        echo "Set password for $gfw_user :"
        passwd $gfw_user
    }

    gen_public_key

    # Enable NAT
    iptables -t nat -F
    echo '1' > /proc/sys/net/ipv4/ip_forward
    iptables -t nat -A POSTROUTING -o $out_iface -j MASQUERADE

    OPTS=
    [ $DEBUG -eq 1 ] && OPTS='-d -D'
    echo '[INFO] Start Obfuscated SSHD'
    $OBF_SSHD -f $OBF_SSHD_CONFIG $OPTS
    lsof -Pn +M | grep "${srv_port} (LISTEN)"
}

add_initd()
{
    echo
}

stop_sshd()
{
    pkill -SIGTERM obf_sshd
}

test -n "$*" || { usage; exit 65; }

case "$1" in
    start)
        start_sshd
        ;;
    key)
        gen_public_key $*
        ;;
    win32)
        mk_win32_cmd
        ;;
    stop)
        stop_sshd
        ;;
    restart)
        sh $0 stop
        sleep 2
        sh $0 start
        ;;
    *)
        usage
        ;;
esac

exit $?


