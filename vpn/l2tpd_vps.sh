#!/bin/bash - 
#===============================================================================
#
#          FILE: l2tpd_vps.sh
# 
#         USAGE: ./l2tpd_vps.sh 
# 
#   DESCRIPTION: L2TP server deploy
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Tony lEE <lüftreich@gmail.com>
#  ORGANIZATION: 
#       CREATED: 08/28/2014 10:44
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

host_addr='255.255.255.255'
vpn_passwd='mxbVpn2014'
out_iface='eth0'
host_config=host.conf

echo_msg()   { echo -e  "\e[31;40m $* \e[0m"; }

bak_file()
{
    test -f $1 || return
    \cp -af ${1}{,.bak}
}

gen_ipsec_secret()
{
    local confile=/etc/ipsec.secrets
    bak_file $confile

    cat > $confile << _EOF
# This file holds shared secrets or RSA private keys for inter-Pluto
# authentication.  See ipsec_pluto(8) manpage, and HTML documentation.

# RSA private key for this host, authenticating it to any other host
# which knows the public part.  Suitable public keys, for ipsec.conf, DNS,
# or configuration of other implementations, can be extracted conveniently
# with "ipsec showhostkey".

# this file is managed with debconf and will contain the automatically created RSA keys
include /var/lib/openswan/ipsec.secrets.inc
# 将IP和密码换成服务器IP和设定的密码 
$host_addr %any: PSK "$vpn_passwd"

_EOF

}

gen_ipsec_conf()
{
    local confile=/etc/ipsec.conf
    bak_file $confile

    cat > $confile << _EOF

# config setup
# 	protostack=netkey
# 	dumpdir=/var/run/pluto/
# 	nat_traversal=yes
# 	virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v4:25.0.0.0/8,%v6:fd00::/8,%v6:fe80::/10

config setup
    nat_traversal=yes
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12
    oe=off
    protostack=netkey
 
conn L2TP-PSK-NAT
    rightsubnet=vhost:%priv
    also=L2TP-PSK-noNAT
 
conn L2TP-PSK-noNAT
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=$host_addr
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any

_EOF

}

gen_xl2tpd_conf()
{
    local confile=/etc/xl2tpd/xl2tpd.conf
    bak_file $confile

    cat > $confile << _EOF

[global]
ipsec saref = yes
 
[lns default]
ip range = 10.1.1.2-10.1.1.255
local ip = 10.1.1.1
refuse chap = yes
refuse pap = yes
require authentication = yes
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes

_EOF

}

gen_xl2tpd_option()
{
    local confile=/etc/ppp/options.xl2tpd
    bak_file $confile

    cat > $confile << _EOF

require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
asyncmap 0
auth
crtscts
lock
hide-password
modem
debug
name l2tpd
proxyarp
lcp-echo-interval 30
lcp-echo-failure 4
_EOF

}

gen_ppp_chap()
{
    local confile=/etc/ppp/chap-secrets
    bak_file $confile

    cat > $confile << _EOF

#user   server  password        ip
user1   l2tpd   $vpn_passwd      *
user2   l2tpd   $vpn_passwd      *
_EOF
}

cd $cur_dir || exit
[ -f ./$host_config ] || {
    echo "host_addr=$host_addr" > $host_config
    echo_msg "Err: invalid host addr, please modify ./$host_config !"
    exit 65
}
. ./$host_config

id | grep 'root' >/dev/null 2>&1 || { echo "Err: must be root account !"; exit 7; }

apt-get -y install openswan  
apt-get -y install xl2tpd

gen_ipsec_secret
gen_ipsec_conf
gen_xl2tpd_conf
gen_xl2tpd_option
gen_ppp_chap

sync; sync; sync

/etc/init.d/xl2tpd restart
/etc/init.d/ipsec  restart

ipsec verify

vps_iface='venet0:0' ## YZM
ifconfig $vps_iface 2>/dev/null && out_iface=${vps_iface}

iptables -t nat -F
iptables -t nat -A POSTROUTING -s 10.1.1.0/24 -o $out_iface -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward




