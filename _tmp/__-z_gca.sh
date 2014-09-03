cur_cmd=`readlink -f $0`
cur_dir=${cur_cmd%/*}
cd $cur_dir/.. || exit

    cat > /tmp/.gitignore << _EOF
obfuscated-openssh-master
*.7z
*key.tgz
login_socks_host
global_proxy.sh
_EOF

git checkout ./ssh/win32
git checkout ./ssh/etc
git checkout ./vpn/host.conf
git diff --name-only
echo -n 'Push To Github ? [Y/n]'
read LUFT
test -n "$*" || { echo 'do nothing.'; exit; }
git commit -a -m "$*"
_FILE=ssh/etc/gfw.conf.bak
[ -f "$_FILE" ] && \cp -vf $_FILE ${_FILE%.bak}

