#!/bin/bash

set -x

domain="$1"
ppp_device="${ppp_device:-ppp0}"

peer_ip="$(ip addr show ppp0 | grep -oP "(?<=peer )[^ ]+" | cut -d "/" -f1)"

for ip in $(dig +short "${domain}"); do
  if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ip route add ${ip} via "${peer_ip}" dev ${ppp_device};
  fi
done;

echo
