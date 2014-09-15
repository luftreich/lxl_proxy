## [Obfuscated SSHD](https://github.com/brl/obfuscated-openssh) Server [Deploy](http://bullshitlie.blogspot.hk/2012/04/ultimate.html)
A global proxy server/client/gateway for Linux, written in `SHELL`.

#### PREREQUISITES
* VPS , SSH supported
* Local LAN gateway

#### Step 1 - Configure VPS
* Edit `ssh/etc/gfw.conf`
* `sh ssh/obfuscated_sshd.sh start`

#### STEP 2 - Configure Gateway
* Copy keyring to GATEWAY, `scp VPS:/$YOUR_DIR/ssh/pkg/*_key.tgz $CUR_DIR/ssh/pkg/*_key.tgz`
* `sh ssh/lan_proxy_gateway.sh restart`
* `sh ssh/lan_proxy_gateway.sh ssh [key]`

#### STEP 3 - Configure your own PC network interface
* Set `gateway` to `$YOUR_GATEWAY_IP`
* Set 'DNS server to `$YOUR_GATEWAY_IP`
```bash
 # e.g.  
 # FOR LINUX USER
 ip route replace default via $YOUR_GATEWAY_IP dev eth0
 echo "nameserver $YOUR_GATEWAY_IP" > /etc/resolv.conf
```
Done ! 

#### TODO LIST
* DNS server in the VPS 
* Full L2TP Supported
* iproute2/ip-rule FWMARK routing policy
* Add SSHD `update-rc.d`


#### LICENSE
Copyright (C) 2014 Tony lEE  <luftreich@gmail.com>  
狂者進取，狷者有所不為! [Follow ME](https://twitter.com/Luftreich)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.
