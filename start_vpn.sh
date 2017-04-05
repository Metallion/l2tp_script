#!/bin/bash

set -xe

if [ -n "$1" ]; then
  source "$1"
fi

#VPN_SERVER_IP
#TARGET_IP=

TUNNEL_INTERFACE="${TUNNEL_INTERFACE:-ppp0}"
CONNECTION_NAME="${CONNECTION_NAME:-L2TP-PSK}"

function get_default_gw_interface() {
  ip route show | grep default | grep -oP "(?<=dev )[^ ]+"
}

function get_tunnel_ip() {
  ip addr show $TUNNEL_INTERFACE | grep "inet\b" | awk '{print $2}'
}

LOCAL_INTERFACE="${LOCAL_INTERFACE:-$(get_default_gw_interface)}"

#ip route add $TARGET_IP via $(get_tunnel_ip)

cat > ~/jantje << EOS
config setup
	virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12
	nat_traversal=yes
	protostack=netkey
	oe=no
	plutoopts="--interface=${LOCAL_INTERFACE}"
conn ${CONNECTION_NAME}
	authby=secret
	pfs=no
	auto=add
	keyingtries=3
	dpddelay=30
	dpdtimeout=120
	dpdaction=clear
	rekey=yes
	ikelifetime=8h
	keylife=1h
	type=transport
	left=%defaultroute
	leftprotoport=17/1701
	right=${VPN_SERVER_IP}
	rightprotoport=17/1701
EOS
