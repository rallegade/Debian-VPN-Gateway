#!/bin/bash

#Check for root access.
if [ $(id -u) != "0" ]; then
	echo "You must be the superuser to run this script."
	exit 1
fi

#Setup
clear
echo "
~~~~~~~~~~~~~~~~~~~~
Welcome to the Debian VPN installer for PIA!
This script is a fork of ShVerni orignal VPN installer for Raspberry pi
modified for working with debian now.
~~~~~~~~~~~~~~~~~~~
"
read -p 'Please type the username of your non root user: ' uservar
echo "
press any key to continue"
read -n 1 -s

clear 
echo "
~~~~~~~~~~~~~~~~~~~~~
Now we need to install some programs, thie will take a while.
~~~~~~~~~~~~~~~~~~~~~
Press any key to continue"
read -n 1 -s

#Intall things
echo iptables-persistent iptables-persistent/autosave_v4 boolean false | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | sudo debconf-set-selections
apt-get update
apt-get upgrade -y
apt-get dist-upgrade -y
apt-get install openvpn dnsmasq unzip gcc make automake autoconf dh-autoreconf file patch perl dh-make debhelper devscripts gnupg lintian quilt libtool pkg-config liblzo2-dev libpam0g-dev libpkcs11-helper1-dev zlib1g-dev iptables-persistent dhcpcd5 -y

clear
echo "
~~~~~~~~~~~~~~~~~~~~~
Now we need to set up the PIA OpenVPN.
~~~~~~~~~~~~~~~~~~~~~
Press any key to continue
"
read -n 1 -s

#Setup PIA
read -p 'PIA username: ' piauservar
read -p 'PIA password: ' passvar

STRONG=0
echo "
Do you wish to use the strongest encryption instead of the default? This will result in slower performance."
select yn in "Yes" "No"; do
    case $yn in
        Yes)
		STRONG=1
		echo "Getting VPN configurations..."
		wget -q https://www.privateinternetaccess.com/openvpn/openvpn-strong.zip -O openvpn.zip
		break;;
        No) 
		echo "Getting VPN configurations..."
		wget -q https://www.privateinternetaccess.com/openvpn/openvpn.zip -O openvpn.zip
		break;;
    esac
done
unzip -o openvpn.zip -d /home/$uservar/PIAopenvpn

#Setup VPN configuration file
chown -R $uservar:$uservar /home/$uservar/PIAopenvpn
files=$(find /home/$uservar/PIAopenvpn/ -maxdepth 1 -type f -regex ".*ovpn")
readarray -t options <<<"$files"
clear
echo "Please select an endpoint to connect to:"
PS3='Select a number: '
select vpnregion in "${options[@]}" ; do
    if (( REPLY > 0 && REPLY <= ${#options[@]} )) ; then
        break
    else
	echo "Invalid option. Try another one."
    fi
done

cp swap_endpoint.sh /home/$uservar/
chown $uservar:$uservar /home/$uservar/swap_endpoint.sh
chmod 755 /home/$uservar/swap_endpoint.sh

if [ "$STRONG" -eq 0 ]; then
	cp /home/$uservar/PIAopenvpn/ca.rsa.2048.crt /home/$uservar/PIAopenvpn/crl.rsa.2048.pem /etc/openvpn/
else
	cp /home/$uservar/PIAopenvpn/ca.rsa.4096.crt /home/$uservar/PIAopenvpn/crl.rsa.4096.pem /etc/openvpn/
fi
cp "$vpnregion" /etc/openvpn/PIAvpn.conf

#Modify configuration
sed -i 's/auth-user-pass/auth-user-pass \/etc\/openvpn\/login/' /etc/openvpn/PIAvpn.conf
if [ "$STRONG" -eq 0 ]; then
	sed -i 's/ca ca.rsa.2048.crt/ca \/etc\/openvpn\/ca.rsa.2048.crt/' /etc/openvpn/PIAvpn.conf
	sed -i 's/crl-verify crl.rsa.2048.pem/crl-verify \/etc\/openvpn\/crl.rsa.2048.pem/' /etc/openvpn/PIAvpn.conf
else
	sed -i 's/ca ca.rsa.4096.crt/ca \/etc\/openvpn\/ca.rsa.4096.crt/' /etc/openvpn/PIAvpn.conf
	sed -i 's/crl-verify crl.rsa.4096.pem/crl-verify \/etc\/openvpn\/crl.rsa.4096.pem/' /etc/openvpn/PIAvpn.conf
fi
echo "auth-nocache" | tee -a /etc/openvpn/PIAvpn.conf
echo -e "script-security 2\nup /etc/openvpn/update-resolv-conf\ndown /etc/openvpn/update-resolv-conf" | tee -a /etc/openvpn/PIAvpn.conf

#Add credentials
rm /etc/openvpn/login
echo -e "${piauservar}\n${passvar}" | tee -a /etc/openvpn/login
chmod 600 /etc/openvpn/login

clear
echo "
~~~~~~~~~~~~~~~~~~~~~
Now OpenVPN needs to update, this will take a while.
~~~~~~~~~~~~~~~~~~~~~
Press any key to continue"
read -n 1 -s

#Openvpn update
wget https://build.openvpn.net/downloads/releases/latest/openvpn-latest-stable.tar.gz
mkdir openvpn-new
gzip -dc openvpn-latest-stable.tar.gz | tar -xf - -C openvpn-new --strip-components=1
cd openvpn-new/
./configure --prefix=/usr
make
make install
cd ..
#Enable Openvpn
systemctl enable openvpn@PIAvpn

cp update_openVPN.sh /home/$uservar/
chown $uservar:$uservar /home/$uservar/update_openVPN.sh
chmod 755 /home/$uservar/update_openVPN.sh

clear
echo "
~~~~~~~~~~~~~~~~~~~~~
Monit will now be installed, this will take a while.
~~~~~~~~~~~~~~~~~~~~~
Press any key to continue"
read -n 1 -s

#Install monit
mkdir monit
wget https://mmonit.com/monit/dist/monit-latest.tar.gz
gzip -dc monit-latest.tar.gz | tar -xf - -C monit --strip-components=1
cd monit/
./configure
make
make install
cd ..

#Copy monit scripts
cp vpnfix.sh /home/$uservar/
chmod 755 /home/$uservar/vpnfix.sh
chown -R $uservar:$uservar /home/$uservar/vpnfix.sh
cp monitrc /etc/
chmod 600 /etc/monitrc
cp monit.service /lib/systemd/system/
chmod 755 /lib/systemd/system/monit.service
#Enable monit
systemctl enable monit.service

#Set up networking
clear
echo "
~~~~~~~~~~~~~~~~~~~~~
Now we need to set up your networking.
You'll need to know the IP address of your current gateway (router)
and you'll need to know the IP address you'd like for your debian server.
~~~~~~~~~~~~~~~~~~~~~
"

read -p 'Internet Gateway IP address: ' gatewayadr
read -p 'Debian server IP address: ' piadr
#Static routes	

#Restore or backup original configuration
if [ -f /etc/network/interfaces.orig ]; then
	cp /etc/network/interfaces.orig /etc/network/interfaces
else
	cp /etc/network/interfaces /etc/network/interfaces.orig
fi

if ! grep -Fq "iface eth0 inet" /etc/network/interfaces; then
	echo -e "auto eth0\niface eth0 inet static\n    address $piadr\n    netmask 255.255.255.0\n    gateway $gatewayadr\n    dns-nameservers 209.222.18.222 209.222.18.218" | tee -a /etc/network/interfaces
else
	sed -i -r "s/iface eth0 inet manual|iface eth0 inet auto/iface eth0 inet static\n    address $piadr\n    netmask 255.255.255.0\n    gateway $gatewayadr\n    dns-nameservers 209.222.18.222 209.222.18.218" /etc/network/interfaces
fi

#Restore or backup original configuration
if [ -f /etc/dhcpcd.conf.orig ]; then
	cp /etc/dhcpcd.conf.orig /etc/dhcpcd.conf
else
	cp /etc/dhcpcd.conf /etc/dhcpcd.conf.orig
fi
echo -e "interface eth0\nstatic\nip_address=${piadr}/24\nstatic routers=${gatewayadr}\nstatic domain_name_servers=209.222.18.222 209.222.18.218" | tee -a  /etc/dhcpcd.conf

#Routing rules
if ! grep -Fxq "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
	echo -e '\n#Enable IP Routing\nnet.ipv4.ip_forward = 1' | tee -a /etc/sysctl.conf
fi
sysctl -p

#Clear out iptables
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t mangle -F
iptables -F
iptables -X

#Add new rules
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -t nat -A PREROUTING -i eth0 -p tcp -m tcp --dport 53 -j DNAT --to-destination 127.0.0.1
iptables -A FORWARD -i tun0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT

#Kill switch
clear
echo "
~~~~~~~~~~~~~~~~~~~~~
Do you wish to enable the kill switch?
This will bolock internet connections when the 
VPN is disconnected.
~~~~~~~~~~~~~~~~~~~~~~
"

select yn in "Yes" "No"; do
    case $yn in
        Yes)
		iptables -I FORWARD -i eth0 ! -o tun0 -j DROP
		iptables -A OUTPUT -o tun0 -m comment --comment "vpn" -j ACCEPT
		iptables -A OUTPUT -o eth0 -p icmp -m comment --comment "icmp" -j ACCEPT
		iptables -A OUTPUT -d "$gatewayadr"/24 -o eth0 -m comment --comment "lan" -j ACCEPT
		iptables -A OUTPUT -o eth0 -p udp -m udp --dport 1198 -m comment --comment "openvpn" -j ACCEPT
		iptables -A OUTPUT -o eth0 -p tcp -m tcp --sport 22 -m comment --comment "ssh" -j ACCEPT
		iptables -A OUTPUT -o eth0 -p udp -m udp --dport 123 -m comment --comment "ntp" -j ACCEPT
		iptables -A OUTPUT -o eth0 -p udp -m udp --dport 53 -m comment --comment "dns" -j ACCEPT
		iptables -A OUTPUT -o eth0 -p tcp -m tcp --dport 53 -m comment --comment "dns" -j ACCEPT
		iptables -A OUTPUT -o eth0 -j DROP;
		break;;
        No) break;;
    esac
done
sleep 1
netfilter-persistent save
systemctl enable netfilter-persistent

#VPN bypass
clear
echo "
~~~~~~~~~~~~~~~~~~~~~~
Do you wish to enable VPN bypass?
This will allow you to specify ip addresses and protocols 
to bypass the VPN. See Read Me for more details.
~~~~~~~~~~~~~~~~~~~~~~
"

select yn in "Yes" "No"; do
    case $yn in
        Yes)
		#Restore or backup original configuration
		if [ -f /etc/iproute2/rt_tables.orig ]; then
			cp /etc/iproute2/rt_tables.orig /etc/iproute2/rt_tables
		else
			cp /etc/iproute2/rt_tables /etc/iproute2/rt_tables.orig
		fi
		echo "105 vpnBypass" | tee -a /etc/iproute2/rt_tables
		
		echo -e "#\x21/bin/bash\n### BEGIN INIT INFO\n# Provides:          rulechecking\n# Required-Start:    \$all\n# Required-Stop:\n# Default-Start:     2 3 4 5\n# Default-Stop:\n# Short-Description: Ensures IP rules are in place.\n### END INIT INFO\n\nRULE_EXISTS=\$(ip rule | grep -c \"vpnBypass\")\n\nif [ \"\$RULE_EXISTS\" -eq 0 ]; then\n\tip rule add fwmark 1 table vpnBypass\nfi\n\nsleep 10\nip route add 128.0.0.0/1 via $gatewayadr dev eth0 table vpnBypass || true\nip route add 0.0.0.0/1 via $gatewayadr dev eth0 table vpnBypass || true" >> vpnbypass
		rm /etc/network/if-up.d/vpnbypass
		cp vpnbypass /etc/network/if-up.d/
		chmod 755 /etc/network/if-up.d/vpnbypass
		rm /etc/init.d/vpnbypass
		cp vpnbypass /etc/init.d/
		chmod 755 /etc/init.d/vpnbypass
		update-rc.d vpnbypass defaults
		cp add_exception.sh /home/$uservar/
		chmod 755 /home/$uservar/add_exception.sh
		chown $uservar:$uservar /home/$uservar/add_exception.sh;
		break;;
        No) break;;
    esac
done

#Clean up
clear
echo "
~~~~~~~~~~~~~~~~~~~~~~
Do you want to delete unnecessary install files?
~~~~~~~~~~~~~~~~~~~~~~
"

select yn in "Yes" "No"; do
    case $yn in
        Yes)
		workingdir=$(pwd)
		cd ..
		rm -R "$workingdir";
		rm /home/$uservar/master.zip
		break;;
        No) break;;
    esac
done

clear
echo "
~~~~~~~~~~~~~~~~~~~~~~
Done! Do you want to reboot?
~~~~~~~~~~~~~~~~~~~~~~
"

select yn in "Yes" "No"; do
    case $yn in
        Yes) 
		( sleep 3 ; reboot ) &
	 	echo "Restarting...";
		break;;
        No) exit 0;;
    esac
done
exit 1
