#!/bin/bash -e
on_chroot << EOT
#netbird on the pi:
apt install ca-certificates curl gnupg -y
curl -L https://pkgs.wiretrustee.com/debian/public.key | sudo apt-key add -
echo 'deb https://pkgs.wiretrustee.com/debian stable main' | sudo tee /etc/apt/sources.list.d/wiretrustee.list

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y wireguard-tools
apt-get install -y netbird
apt install -y hostapd
systemctl unmask hostapd
systemctl enable hostapd
apt install -y dnsmasq
apt install -y netfilter-persistent iptables-persistent

cat <<EOF> /etc/dhcpcd.conf
interface wlan0
	static ip_address=192.168.4.1/24
	nohook wpa_supplicant
EOF
#
cat <<EOF> /etc/sysctl.d/routed-ap.conf
net.ipv4.ip_forward=1
EOF

#mv /etc/dnsmasq.conf /etc/dnsmasq.conf.ORIGINAL

cat <<EOF> /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.100,255.255.255.0,24h
domain=network
address=/boring.network/192.168.4.1
addn-hosts=/etc/dnsmasq.hosts
EOF

cat <<EOF> /etc/dnsmasq.hosts
192.168.4.1 unconfigured.insecure.boring.surf.
EOF

rfkill unblock all

#mv /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.ORIGINAL

cat <<EOF> /etc/hostapd/hostapd.conf
country_code=US
interface=wlan0
# append random 4 digit to boring ssid
RANDOM_SUFFIX=$(printf "%04d" $((RANDOM % 10000)))
ssid=boring-${RANDOM_SUFFIX}
hw_mode=g
channel=7
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=motherbored
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

systemctl enable hostapd

cat <<EOF> /etc/network/interfaces.d/eth0
auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
EOF

sudo apt install -y urfkill

cat <<EOF> /etc/urfkill/urfkill.conf
user=root
persist=true
EOF

mkdir -p /boringupdate
cd /boringupdate
rm -rf boringfiles.tgz ||true
wget https://s3.us-east-2.amazonaws.com/boringfiles.dank.earth/boringfiles.tgz
tar -xzvf boringfiles.tgz
cp netbird /bin/netbird
cp boring.service /lib/systemd/system/boring.service
cp boringup.sh /usr/local/bin/boringup.sh
cp boring.sh /usr/local/bin/boring.sh
cp hostapd.service /lib/systemd/system/hostapd.service
systemctl enable boring

# install node
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
#curl -fsSL https://deb.nodesource.com/setup_current.x | bash -
apt-get install -y nodejs git

mkdir -p /usr/local/boring
cd /usr/local/boring

# install connect-pi
rm -rf connect-pi.tgz
wget https://s3.us-east-2.amazonaws.com/boringfiles.dank.earth/connect-pi.tgz
tar -xzvf connect-pi.tgz
cd connect-pi
npm install -y
npm run build
#service file
cp connect-pi.service /lib/systemd/system/connect-pi.service
systemctl enable connect-pi

# install nginx configure SSL for default insecure site ops
apt install -y nginx
cp connect-pi.nginx.conf /etc/nginx/sites-enabled/default
systemctl enable nginx
mkdir -p /usr/local/boring/certs
cp fullchain.pem /usr/local/boring/certs/fullchain.pem
cp privkey.pem /usr/local/boring/certs/privkey.pem

# influx
# telegraf
# wget https://dl.influxdata.com/telegraf/releases/telegraf-1.24.0_linux_armhf.tar.gz

wget -q https://repos.influxdata.com/influxdata-archive_compat.key

echo '393e8779c89ac8d958f81f942f9ad7fb82a25e133faddaf92e15b16e6ac9ce4c influxdata-archive_compat.key' | sha256sum -c && cat influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list

apt-get update
apt-get install -y telegraf

# this can't be done here, has to get done on boot
#setcap CAP_NET_ADMIN+epi /usr/bin/telegraf 

cp /boringupdate/telegraf.env /etc/default/telegraf
cp /boringupdate/telegraf.conf /etc/telegraf/telegraf.conf
systemctl enable telegraf

apt-get install -y systemd-journal-remote
systemctl enable systemd-journal-gatewayd

EOT
