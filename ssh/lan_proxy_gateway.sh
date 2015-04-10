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
stop_ssh_file=/tmp/.STOP_SSH
ssh_pid_file=/tmp/.PID_SSH
touch $ssh_pid_file

cd $cur_dir
. ./init_func.sh

usage()
{
    cat << _EOF

    Usage: ${0##*/} {start|stop|restart|reload}

           ${0##*/} start        # Enable global proxy gateway

           ${0##*/} ssh [key]    # Start SSH Tunnel, PubkeyAuthentication
           ${0##*/} ssh [pass]   # Start SSH Tunnel, PasswordAuthentication, Default option
           ${0##*/} ssh [pass|key] debug # DEBUG <-p|-k>
        
_EOF
    gen_init_start
}

save_log()
{
    echo "`date +%F-%T` <$*>" >> /tmp/.LOG_SSH
}

pre_geoip_env()
{
    local DSTDIR=/usr/share/xt_geoip
    ls $DSTDIR/[BL]E >/dev/null && return

    apt-get update
    apt-get -y install libtext-csv-xs-perl xtables-addons-common
    cd /tmp || exit
    mkdir -p $DSTDIR
    /usr/lib/xtables-addons/xt_geoip_dl
    /usr/lib/xtables-addons/xt_geoip_build -D $DSTDIR GeoIP*.csv
    sync; sync
    ls $DSTDIR/[BL]E >/dev/null || { echo_msg "Err: Install GeoIP Failed !"; exit 7; }
}

pre_dnscrypt_env()
{
   test -x $DNSCRYPT_PROXY_EXE && return
   apt-get -y install pdnsd redsocks dnsutils autossh expect lsof sshpass
   
   cd $pkg_dir || exit
   wget -c -t 3 http://download.dnscrypt.org/dnscrypt-proxy/dnscrypt-proxy-1.3.3.tar.bz2
   wget -c -t 3 http://download.libsodium.org/libsodium/releases/libsodium-0.5.0.tar.gz

   tar xf libsodium-*.tar.gz
   cd libsodium-* && { ./configure; make; make install; cd -; }

   tar xf dnscrypt-proxy-*.tar.bz2
   local HOST_OPTS=
   uname -m | grep 'x86_64' && HOST_OPTS='--host=x86_64-unknown-linux-gnu'
   cd dnscrypt-proxy-* && { ./configure  $HOST_OPTS; make; make install; cd -; }

   test -x $DNSCRYPT_PROXY_EXE || { echo_msg "Err: Install dnscrypt-proxy Failed !"; exit 7; }
}

pre_all_env()
{
    pre_geoip_env     || exit
    pre_dnscrypt_env  || exit
    pre_polipo_env    || exit
}

stop_socks5_forward()
{
    ps -ef | grep 'expec[t]' | awk '{print $2}' | xargs kill -9
    sleep 2
    ps -ef | grep 'expec[t]' | awk '{print $2}' | xargs kill -9
    pkill -SIGKILL autossh
    pkill -SIGKILL sshpass
    pkill -SIGKILL ${OBF_SSH##*/}
}

kill_ssh_fork()
{
    grep '[0-9]' $ssh_pid_file && {
        read PID_SSH < $ssh_pid_file
        kill -9 $PID_SSH
        sleep 2
        kill -9 $PID_SSH 2>/dev/null
        >$ssh_pid_file
    }
}

stop_all_ssh()
{
    kill_ssh_fork
    stop_socks5_forward
}

gen_init_start()
{
    cat > $cur_dir/start.sh << _EOF
#!/bin/bash

sh $cur_cmd restart
sh $cur_cmd ssh 2>&1 | tee /dev/null
# sh $cur_cmd ssh key 2>&1 | tee /dev/null

_EOF
    chmod +x $cur_dir/start.sh
}

alarm_trigger()
{
    save_log "SIGALRM"
    stop_socks5_forward
}

timing_reconnect()
{
    ## 定时主动发送复位信号，防止出现无效连接, 非必需
    [ -f /tmp/.LOCK_ALARM ] && return
    {
        touch /tmp/.LOCK_ALARM
        trap 'exit 255' INT TERM KILL QUIT
        while true; do
            sleep 7200
            cat $ssh_pid_file | xargs kill -SIGALRM
            # pkill -SIGUSR1 autossh
        done
    } &
    echo $! >/tmp/.PID_ALARM
}

local_socks5_forward()
{
    # 本地SOCKS5 FORWARD

    pre_install
    cd  $cur_dir || exit

    EXEC_OBF_SSH=${OBF_SSH}_exec
    [ -x $EXEC_OBF_SSH ] || {
        echo -n 'Please Input Root '
        su -c "> $EXEC_OBF_SSH; chmod 777 $EXEC_OBF_SSH"
    }
    echo "exec $OBF_SSH -Z $key_code \"\$@\"" > $EXEC_OBF_SSH; sync

    export AUTOSSH_PATH=$EXEC_OBF_SSH
    local _OPTS='-t -o StrictHostKeyChecking=no -o TCPKeepAlive=yes -o ServerAliveInterval=60'
    local mon_port=43210 ## monitoring port
    local i=0
    local _DEBUG='NO'

    if [ $# -eq 1 ]; then
        param='pass'
    else
        param=$2
        shift
        [ $# -ge 2 ] && {
            [ "$2" = "debug" ] && _DEBUG='YES'
        }
    fi
    case $param in
        sig)
            cat $ssh_pid_file | xargs kill -SIGALRM
            return
            ;;
        st)
            clear
            ps -ef | grep --color=auto -H -E 'expec[t]|ss[h]|slee[p]|[d]ns|[p]olipo'
            echo "<FORK_PID> : `cat $ssh_pid_file`"
            return
            ;;
        stop)
            stop_all_ssh
            return
            ;;
        key)
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
            if [ "$_DEBUG" = "YES" ]; then
                $OBF_SSH $_OPTS  \
                    -L ${mon_port}:127.0.0.1:${mon_port} \
                    -C -N -D $forward_port \
                    -Z $key_code -v \
                    ${host_name}
            else
                autossh -M $mon_port -f -C -N -D $forward_port $host_name
            fi

            # {
            #     while true; do
            #         sleep 5
            #         [ -f $stop_ssh_file ] && break
            #         lsof -i:${mon_port} >/dev/null && continue
            #         $OBF_SSH $_OPTS -f \
            #             -L ${mon_port}:127.0.0.1:${mon_port} \
            #             -C -N -D $forward_port \
            #             -Z $key_code -v \
            #             ${host_name}
            #         let i+=1
            #         echo "`date +%F-%T` <$i>" >> /tmp/.log_ssh
            #         [ $i -eq 10 ] && break
            #     done
            # } &

            # ssh  -C -N -D $forward_port server -v ## LAN TEST
            ;;
        pass)
            # Passwordauthentication
            login_ssh_exec=./login_socks_host
            cat > $login_ssh_exec << _EOF
#!/bin/sh
sshpass -p "$passwd" \
    $OBF_SSH $_OPTS  \
    -L ${mon_port}:127.0.0.1:${mon_port} \
    -C -N -D $forward_port \
    -Z $key_code \
    -p $srv_port -v \
    $gfw_user@$host_addr

_EOF

            chmod +x $login_ssh_exec

            if [ "$_DEBUG" = "YES" ]; then
                $login_ssh_exec
                return
            fi

            # DAEMON
            sed -i 's/\-v/\-f/g' $login_ssh_exec
            sync
            timing_reconnect
            {
                # trap 'exit 7' TERM
                trap 'alarm_trigger' ALRM

                local T=0
                while true; do
                    let T+=1
                    [ $T -eq 20 ] && T=1
                    sleep `expr $T \* 5`
                    [ -f $stop_ssh_file ] && break
                    lsof -i:${mon_port} >/dev/null && continue
                    # Start
                    stop_socks5_forward
                    sleep 2
                    $login_ssh_exec
                    let i+=1
                    save_log "$i"
                    # [ $i -eq 50 ] && {
                    #     save_log "EXIT"
                    #     break
                    # }
                done
            } &
            echo $! >$ssh_pid_file
            ;;
        *)
            exit $?
            ;;
    esac
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
    sed -i 's/START_DAEMON=no/START_DAEMON=yes/g' /usr/share/pdnsd/pdnsd-default
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
    /etc/init.d/polipo stop  ; sleep 2

    pkill -SIGHUP dnsmasq
    pkill dnsmasq
    pkill pdnsd
    pkill dnscrypt-proxy 
    pkill redsocks

    stop_all_ssh
}

clear_iptables_rules()
{
    # 清除 iptables 规则

    iptables -t nat -F
    iptables -t nat -X
    iptables -t nat -Z
    iptables -t mangle -F

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

enable_snat()
{
    # Only NAT Forward
    echo "1" > /proc/sys/net/ipv4/ip_forward
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -t nat --list
}

pre_polipo_env()
{
    local confFile=/etc/polipo/config
    type polipo || {
        apt-get -y install polipo
        \cp -f $confFile ${confFile}.bak || true
        type polipo || exit 65
    }
}

boot_polipo()
{

    local confFile=/etc/polipo/config
    cat > $confFile << _EOS
proxyAddress = "0.0.0.0"    # IPv4 only
proxyPort = 8123
allowedPorts = 1-65535
socksParentProxy = "localhost:$forward_port"
socksProxyType = socks5
_EOS

    sync
    /etc/init.d/polipo restart
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


    # Redirect normal HTTP and HTTPS traffic
    local _OPTS=
    echo "$*" | grep -q '\-\-geoip' && _OPTS='-m geoip ! --dst-cc CN'
    iptables -t nat -A REDSOCKS -p tcp --dport 80  $_OPTS -j REDIRECT --to-ports $redsocks_listen_port
    iptables -t nat -A REDSOCKS -p tcp --dport 443 $_OPTS -j REDIRECT --to-ports $redsocks_listen_port

    # 重定向全部TCP,非必需
    # iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports $redsocks_listen_port

    # iptables -t mangle -A POSTROUTING -j TEE --gateway $sniff_host
    # iptables -t mangle -A PREROUTING  -j TEE --gateway $sniff_host

    # 本地,非必需
    # iptables -t nat -A OUTPUT -p tcp -j REDSOCKS
    # 子网
    iptables -t nat -A PREROUTING -p tcp -j REDSOCKS

    # 劫持DNS, Anti-GFW
    iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53

    # 使能SNAT
    enable_snat
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
        pre_all_env
        boot_redsocks
        boot_polipo
        dns_proxy_srv
        gen_iptables_rules "$*"
        ;;
    stop)
        probe_root
        # pre_all_env
        clear_iptables_rules
        kill_all_daemon
        ;;
    restart|reload)
        sh $cur_cmd stop
        sleep 2
        sh $cur_cmd start --geoip
        ;;
    nat)
        probe_root
        sh $cur_cmd stop
        sleep 3
        enable_snat
        ;;
    -p|--debug-pass)
        sh -x $cur_cmd ssh pass debug
        ;;
    -k|--debug-key)
        sh -x $cur_cmd ssh key  debug
        ;;
    geoip)
        pre_geoip_env
        exit 0
        ;;
    *)
        usage
        exit 1
        ;;
esac

exit $?

