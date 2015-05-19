
x_cmd=`readlink -f $0`
x_dir=${x_cmd%/*}
cur_dir=${cur_dir:=$x_dir}

host_addr='255.255.255.255' # your vps 
gfw_user='usergfw'  # valid client user
passwd='NULL'       # password auth
key_file='gfw'      # private key
key_code='szmxb'    # obfuscated word
forward_port='7070' # local forward port
srv_port='2222'     # host port
gw_self='no'        # proxy lan GW itself

pkg_dir=$cur_dir/pkg
etc_dir=$cur_dir/etc
mkdir -p $pkg_dir $etc_dir

host_config=$etc_dir/gfw.conf
src_dir='obfuscated-openssh-master'
bld_dir=$pkg_dir/$src_dir
OBF_SSHD=$bld_dir/obf_sshd
OBF_SSHD_CONFIG=$bld_dir/sshd_config_obf
OBF_HOST_KEY=$bld_dir/ssh_host_rsa_key
OBF_SSH=$bld_dir/ssh_obf

HOST_OPTS=
uname -m | grep 'x86_64' && HOST_OPTS='--host=x86_64-unknown-linux-gnu'
export HOST_OPTS

probe_root()
{
    id | grep 'root' >/dev/null 2>&1 || {
        echo "Err: must be root account !"
        exit 7
    }
}

echo_msg() { echo -e  "\e[31;40m $* \e[0m"; }

pre_install()
{
    if [ ! -e $OBF_SSHD ]; then
        probe_root
        # apt-get  update
        # apt-get -y install gcc
        # apt-get -y install build-essential
        apt-get -y install zlib1g-dev
        apt-get -y install libssl-dev

        cd $pkg_dir || exit
        # wget -c -O ${src_dir}.zip http://github.com/brl/obfuscated-openssh/archive/master.zip
        \rm $src_dir -rf; sync
        unzip ${src_dir}.zip
        cd $src_dir || exit
        ./configure $HOST_OPTS --prefix=/usr/local
        make
        # make install

        if [ -f ./sshd ]; then
            mv ./sshd $OBF_SSHD
            mv ./ssh $OBF_SSH
        else
            echo_msg "Err: Install Obfuscated-openssh Failed !"
            exit 65
        fi
    fi
}

[ -f $host_config ] || {
    cat > $host_config << _EOF
#HOST                 #USER       #PASSWORD   #KEY_FILE   #KEY_CODE     #FORWARD_PORT   #SRV_PORT #GW_SELF
#192.168.1.20         usergfw     usergfw     gfwLAN         mxb902        7070            2222     no
$host_addr         $gfw_user     $passwd     $key_file         $key_code      $forward_port      $srv_port    $gw_self
_EOF
    echo_msg "WARNING: Invalid host addr, please check etc/${host_config##*/}!"
    # exit 65
}

exec 9<&0 <$host_config
while read host_addr gfw_user passwd key_file key_code forward_port srv_port gw_self; do
    # case "$host_addr" in (""|\#*) continue; ;; esac
    echo $host_addr | grep -q '^\#' || break
done
exec 0<&9 9<&-

# echo $host_addr $gfw_user $passwd $key_file $key_code $forward_port $srv_port
export host_addr gfw_user passwd key_file key_code forward_port srv_port gw_self
export host_name=$key_file
export key_tar_file=$pkg_dir/${key_file}_key.tgz
export win32_key_file=${key_file}.win32

