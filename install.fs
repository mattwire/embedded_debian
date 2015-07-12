#!/bin/bash

echo -n "Copying files to system locations..."

cp ./fs/etc/* /etc/ -rf
cp ./fs/sbin/* /sbin/ -rf
cp ./fs/opt/* /opt/ -rf

echo "Done"

echo -n "Configure DHCP/DNS..."
rm -rf /var/lib/dhcp
ln -s /tmp /var/lib/dhcp

rm /etc/resolv.conf
ln -s /tmp/resolv.conf /etc/resolv.conf

echo "Done"

echo -n "Linking rc scripts..."
ln -s /opt/bin/shutdown /etc/init.d/shutdown
insserv -d shutdown
echo "Done"

echo -n "Restarting processes..."
/etc/init.d/ntp restart
echo "Done"

