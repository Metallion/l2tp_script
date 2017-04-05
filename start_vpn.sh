#!/bin/bash

if [ -n "$1" ]; then
  source "$1"
fi

#TARGET_IP=
LOCAL_INTERFACE="${LOCAL_INTERFACE:-eth0}"
TUNNEL_INTERFACE="${TUNNEL_INTERFACE:-ppp0}"

function get_tunnel_ip() {
  ip addr show $TUNNEL_INTERFACE | grep "inet\b" | awk '{print $2}'
}

ip route add $TARGET_IP via $(get_tunnel_ip)
