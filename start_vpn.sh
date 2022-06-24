#!/bin/bash

set -xe

if [[ "$EUID" -ne "0" ]]; then
  echo "Permission denied. Run this as root or sudo."
  exit 1
fi

if [ -n "$1" ]; then
  source "$1"
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Optional variables
BACKUP_CONFIG_FILES="${BACKUP_CONFIG_FILES:-true}"

TUNNEL_INTERFACE="${TUNNEL_INTERFACE:-ppp0}"
CONNECTION_NAME="${CONNECTION_NAME:-L2TP-PSK}"

IPSEC_CONFIG="${IPSEC_CONFIG:-/etc/ipsec.conf}"
IPSEC_SECRETS="${IPSEC_SECRETS:-/etc/ipsec.secrets}"

XL2TPD_CONFIG="${XL2TPD_CONFIG:-/etc/xl2tpd/xl2tpd.conf}"
XL2TPD_CLIENT="${XL2TPD_CLIENT:-/etc/ppp/options.l2tpd.client}"

# Can also be: mschap-v2
L2TP_AUTHENTICATION="${L2TP_AUTHENTICATION:-pap}"

# Usage and dependency checks
dependencies=(L2TP_SERVER_IP L2TP_USER_NAME L2TP_PASSWORD IPSEC_PRE_SHARED_KEY)
function print_usage() {
cat << EOS
# Set the following environment variables to match the L2TP/IPSec VPN that you're connecting to.
#
# TARGET_IP_RANGES means a space separated list of CIDR notation of the destination IP range you wish to route through the VPN tunnel.
#
# TARGET_DOMAINS means a space separated list of domain names you wish to route through the VPN. For example if you want all connections to www.example.com to go through the VPN, you would add that domain here.
#
# The rest should be self explanatory.
#
# You can also put these in another file and pass that as an argument.

EOS


for i in ${dependencies[@]}; do
  echo "$i"
done
}

for i in ${dependencies[@]}; do
  if [[ -z $(printf '%s\n' "${!i}") ]]; then
    print_usage

    echo
    echo "## ERROR ##"
    echo "$i was not set."
    exit 2
  fi
done

function get_default_gw_interface() {
  ip route show | grep default | grep -oP "(?<=dev )[^ ]+"
}
LOCAL_INTERFACE="${LOCAL_INTERFACE:-$(get_default_gw_interface)}"

function backup_file() {
  local file="$1"

  if [[ "${BACKUP_CONFIG_FILES}" == "true"  && -f "${file}" ]]; then
    cp ${file} ${file}.$(date -Is)
  fi
}

# Create the ipsec config file
backup_file ${IPSEC_CONFIG}
cat > ${IPSEC_CONFIG} << EOS
conn %default
        keyingtries=0

conn ${CONNECTION_NAME}
    type=transport
    auto=start
    keyexchange=ikev1
    authby=psk
    left=%defaultroute
    right=${L2TP_SERVER_IP}
    ike=aes256-sha256-modp1024
    esp=aes256-sha256-modp1024
    keyingtries=%forever
    ikelifetime=28800s
    lifetime=28800s
    dpddelay=10s
    dpdtimeout=50s
    dpdaction=restart
EOS

# Add the ipsec secrets if not there already
backup_file ${IPSEC_SECRETS}
secret="0.0.0.0 : PSK \"${IPSEC_PRE_SHARED_KEY}\""
set +e
[[ -f "${IPSEC_SECRETS}" ]] && grep -q "${secret}" "${IPSEC_SECRETS}"
if [[ "$?" != "0" ]]; then
  echo "${secret}" >> "${IPSEC_SECRETS}"
fi
set -e

# Set up xl2tpd
backup_file ${XL2TPD_CONFIG}
cat > ${XL2TPD_CONFIG} << EOS
[lac vpn-connection]
lns = ${L2TP_SERVER_IP}
ppp debug = yes
pppoptfile = /etc/ppp/options.l2tpd.client
length bit = yes
EOS

backup_file ${XL2TPD_CLIENT}
cat > ${XL2TPD_CLIENT} << EOS
ipcp-accept-local
ipcp-accept-remote
refuse-eap
require-${L2TP_AUTHENTICATION}
noccp
noauth
idle 1800
mtu 1410
mru 1410
defaultroute
usepeerdns
debug
connect-delay 5000
name ${L2TP_USER_NAME}
password ${L2TP_PASSWORD}
EOS

# Start openswan (= ipsec) and xl2tpd
systemctl start strongswan
systemctl start xl2tpd

ipsec restart

# Create the tunnel interface
echo "c vpn-connection" > /var/run/xl2tpd/l2tp-control

# Give it some time to bring up the ppp interface
sleep 2

# Route the target IP range through the tunnel
tunnel_ip=$(ip addr show $TUNNEL_INTERFACE | grep "inet\b" | awk '{print $2}')
for ip_range in $TARGET_IP_RANGE; do
  if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ip route add "$ip_range" via "$tunnel_ip" dev "${TUNNEL_INTERFACE}"
  fi
done

# Get IPs for target domains and route them too.
for domain in $TARGET_DOMAINS; do
  "$SCRIPT_DIR/route_domain_through_vpn.sh" "${domain}" "$TUNNEL_INTERFACE"
done
