#!/bin/bash - 
#===============================================================================
#
#          FILE: lan_proxy_gateway.sh
# 
#         USAGE: ./lan_proxy_gateway.sh 
# 
#   DESCRIPTION: Lan proxy gateway
# 
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Tony lEE <lüftreich@gmail.com>
#  ORGANIZATION: 
#       CREATED: 2014年05月16日 16时01分49秒 HKT
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
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:="/lib:/usr/lib:/usr/local/lib"}

export upstream_dns_host='127.0.0.1'
export upstream_dns_port='2053'  # 不能与默认udp53端口冲突
export redsocks_listen_port='54321'
export sniff_host='192.168.1.125'
DNSCRYPT_PROXY_EXE='/usr/local/sbin/dnscrypt-proxy'

cd $cur_dir
. ./init_func.sh

usage()
{
    cat << _EOF

   Usage: ${0##*/} {start|stop|restart|reload}

     ${0##*/} start      # Enable global proxy gateway
     ${0##*/} ssh        # Start local socks5 forward
     ${0##*/} ssh key    # PubkeyAuthentication
     ${0##*/} clear      # Clear iptables rules
        
_EOF
}

pre_env()
{
   test -x $DNSCRYPT_PROXY_EXE && return
   probe_root
   apt-get -y install pdnsd redsocks dnsutils
   
   cd $pkg_dir || exit
   wget -c -t 3 http://download.dnscrypt.org/dnscrypt-proxy/dnscrypt-proxy-1.3.3.tar.bz2
   wget -c -t 3 http://download.libsodium.org/libsodium/releases/libsodium-0.5.0.tar.gz

   tar xf libsodium-*.tar.gz
   cd libsodium-* && { ./configure; make; make install; cd -; }

   tar xf dnscrypt-proxy-*.tar.bz2
   cd dnscrypt-proxy-* && { ./configure --host=x86_64-unknown-linux-gnu; make; make install; cd -; }

   test -x $DNSCRYPT_PROXY_EXE || { echo_msg "Err: Install dnscrypt-proxy Failed !"; exit 7; }
}

local_socks5_forward()
{
    # 本地SOCKS5 FORWARD

    pre_install
    cd  $cur_dir || exit
    local _OPTS='-o StrictHostKeyChecking=no -o TCPKeepAlive=yes -o ServerAliveInterval=60'

    if echo "$*" | grep -q 'key'; then
        # Pubkeyauthentication
        grep "host ${host_name}" ~/.ssh/config || {
            cat >> ~/.ssh/config << _EOF
host ${host_name}
    user $gfw_user
    hostname $host_addr
    port $srv_port
    identityfile ~/.ssh/${key_file}
_EOF
        }

        [ -f ~/.ssh/${key_file} ] || echo_msg "Warn: private key < ~/.ssh/${key_file} > not exist !"

        $OBF_SSH $_OPTS -C -N -D $forward_port ${host_name} -Z $key_code -v

        # ssh  -C -N -D $forward_port server -v ## LAN TEST
    else
        # Passwordauthentication
        login_ssh_exec=./login_socks_host
        cat > $login_ssh_exec << _EOF
#!/usr/bin/expect

set timeout 120
set host_addr $host_addr
set gfw_user $gfw_user

spawn -noecho $OBF_SSH $_OPTS  -C -N -D $forward_port $gfw_user@$host_addr -Z $key_code -p $srv_port -v

# expect -re {    # 等待响应，第一次登录往往会提示是否永久保存 RSA 到本机的 know hosts 列表中；等到回答后，在提示输出密码；
#       "(yes/no)?" {
#            send "yes\n"
#            expect "Password:"
#            send   "$passwd\n"
#       }
#       "Password:"  {
#           send "$passwd\n"
#       }
# }

expect -re 密码：|Password:|password:
send "$passwd\r"
interact

_EOF

    chmod +x $login_ssh_exec
    $login_ssh_exec

    fi

}

boot_redsocks()
{
    redsocks_configfile=${etc_dir}/redsocks.conf

    cat > $redsocks_configfile << _EOF
base {
    log_debug = off;
    log_info = off;
    daemon = on;
    redirector= iptables;
}

redsocks {

    local_ip = 0.0.0.0;
    local_port = $redsocks_listen_port;

    // proxy server
    ip = 127.0.0.1;
    port = 7070;

	// known types: socks4, socks5, http-connect, http-relay
    type = socks5;
}
_EOF

    redsocks -c ${redsocks_configfile}
}

dns_proxy_srv()
{
    # DNS加密代理

    sed -i 's/START_DAEMON=no/START_DAEMON=yes/g' /etc/default/pdnsd 
    pdnsd_configfile=/etc/pdnsd.conf

    cat > $pdnsd_configfile << _EOF
global {
        perm_cache=65536;
        cache_dir="/var/cache/pdnsd";
        pid_file = /var/run/pdnsd.pid;
        run_as="nobody";
        server_ip = any;  # Use eth0 here if you want to allow other
                                # machines on your network to query pdnsd.
        status_ctl = on;
        query_method=tcp_only;
        use_nss=off;
        min_ttl=1d;
        max_ttl=1w;        # One week.
        timeout=10;        # Global timeout option (10 seconds).
        par_queries=1;
        neg_rrs_pol=on;
}

server {
        label= "local dnscrypt";
        ip = ${upstream_dns_host};    # 上游dns服务器
        port = ${upstream_dns_port};  # dnscrypt的监听端口
        timeout=10;
        uptest=query;  
  //      edns_query=no;  
}

server {  
        label= "google dns";   # 备用 dns
        ip = 8.8.8.8,8.8.4.4;
        timeout=10;
        uptest=ping;  
   //     edns_query=no;  
}

// 可以通过pdnsd-ctl status 查看pdnsd运行状态

_EOF

    # 转发opendns到本地
    $DNSCRYPT_PROXY_EXE \
        --local-address=${upstream_dns_host}:${upstream_dns_port} \
        --logfile=/var/log/dnscrypt.log \
        --daemonize

    # DNS 服务器
    /etc/init.d/pdnsd restart
    sleep 3

    echo 'nameserver 127.0.0.1' > /etc/resolv.conf

    dig +notcp @8.8.8.8 youtube.com
    dig youtube.com
    lsof -Pn +M | grep '53 (LISTEN)'


}

kill_all_daemon()
{
    /etc/init.d/dnsmasq stop ; sleep 2
    /etc/init.d/bind9 stop   ; sleep 2
    /etc/init.d/pdnsd stop   ; sleep 2

    pkill -SIGHUP dnsmasq
    pkill dnsmasq
    pkill pdnsd
    pkill dnscrypt-proxy 
    pkill redsocks
}

clear_iptables_rules()
{
    # 清除 iptables 规则

    iptables -t nat -F
    iptables -t nat -X
    iptables -t nat -Z

    # iptables -t mangle -D POSTROUTING -j TEE --gateway $sniff_host 2>/dev/null
    # iptables -t mangle -D PREROUTING  -j TEE --gateway $sniff_host 2>/dev/null

    iptables -t nat -D PREROUTING -p tcp -j REDSOCKS 2>/dev/null
    iptables -t nat -D OUTPUT     -p tcp -j REDSOCKS 2>/dev/null
    iptables -t nat -F REDSOCKS 2>/dev/null
    iptables -t nat -X REDSOCKS 2>/dev/null

    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT

    # iptables -P FORWARD DROP  #只有FORWARD链默认DROP
    iptables -P FORWARD ACCEPT
    iptables -t nat -P PREROUTING ACCEPT
    iptables -t nat -P POSTROUTING ACCEPT
    iptables -t nat -P OUTPUT ACCEPT

    echo "0" > /proc/sys/net/ipv4/ip_forward
    echo 'nameserver 8.8.8.8' > /etc/resolv.conf

}

gen_iptables_rules()
{
    ##
    iptables -t nat -N REDSOCKS

    # Do not redirect traffic to the followign address ranges
    iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
    iptables -t nat -A REDSOCKS -d 192.168.0.0/16 -j RETURN
    iptables -t nat -A REDSOCKS -d 10.8.0.0/16 -j RETURN
    iptables -t nat -A REDSOCKS -d 224.0.0.0/4 -j RETURN
    iptables -t nat -A REDSOCKS -d 240.0.0.0/4 -j RETURN

    # Anti-GFW
    # iptables -A INPUT -p udp --sport 53 -m state --state ESTABLISHED -m gfw -j DROP -m comment --comment "drop gfw dns hijacks"

    # 如果使用国外代理的话，走 UDP 的 DNS 请求转到 redsocks，redsocks 会让其使用 TCP 重试
    # iptables -t nat -A REDSOCKS -p udp --dport 53 -j REDIRECT --to-ports 2053
    # 如果走 TCP 的 DNS 请求也需要代理的话，使用下边这句。一般不需要
    # iptables -t nat -A REDSOCKS -p tcp --dport 53 -j REDIRECT --to-ports 2053

    # Redirect normal HTTP and HTTPS traffic
    iptables -t nat -A REDSOCKS -p tcp --dport 80 -j REDIRECT --to-ports $redsocks_listen_port
    iptables -t nat -A REDSOCKS -p tcp --dport 443 -j REDIRECT --to-ports $redsocks_listen_port

    # 重定向全部TCP
    # iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports $redsocks_listen_port

    # iptables -t mangle -A POSTROUTING -j TEE --gateway $sniff_host
    # iptables -t mangle -A PREROUTING  -j TEE --gateway $sniff_host

    ##############################################################################
    # 本地全局代理
    # iptables -t nat -A OUTPUT -p tcp -j REDSOCKS

    # 劫持dns查询
    iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53
    iptables -t nat -A PREROUTING -p tcp -j REDSOCKS

    # 使能Forward
    echo "1" > /proc/sys/net/ipv4/ip_forward
    iptables -t nat --list
}

enable_nat()
{
    # Only NAT Forward
    echo "1" > /proc/sys/net/ipv4/ip_forward
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -t nat --list
}

#### main prog
test -n "$*" || { usage; exit 65; }

case $1 in
    clear)
        probe_root
        clear_iptables_rules
        ;;
    ssh)
        local_socks5_forward $*
        ;;
    start)
        probe_root
        pre_env
        boot_redsocks
        dns_proxy_srv
        gen_iptables_rules
        ;;
    stop)
        probe_root
        pre_env
        clear_iptables_rules
        kill_all_daemon
        ;;
    restart|reload)
        sh $cur_cmd stop
        sleep 2
        sh $cur_cmd start
        ;;
    nat)
        probe_root
        sh $cur_cmd stop
        sleep 3
        enable_nat
        ;;
    *)
        usage
        exit 1
        ;;
esac

exit $?
