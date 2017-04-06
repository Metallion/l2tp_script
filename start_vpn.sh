#!/bin/bash

set -xe

if [[ "$EUID" -ne "0" ]]; then
  echo "Permission denied. Run this as root or sudo."
  exit 1
fi

if [ -n "$1" ]; then
  source "$1"
fi

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
dependencies=(L2TP_SERVER_IP L2TP_USER_NAME L2TP_PASSWORD IPSEC_PRE_SHARED_KEY TARGET_IP_RANGE)
function print_usage() {
cat << EOS
# Set the following environment variables to match the L2TP/IPSec VPN that you're connecting to.
#
# TARGET_IP_RANGE means a CIDR notation of the destination IP range you wish to route through the VPN tunnel.
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
	right=${L2TP_SERVER_IP}
	rightprotoport=17/1701
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
systemctl start openswan
systemctl start xl2tpd

# Give openswan a bit of time to initialize ipsec before we bring up the connection
sleep 1
ipsec auto --up ${CONNECTION_NAME}

# Create the tunnel interface
echo "c vpn-connection" > /var/run/xl2tpd/l2tp-control

# Give it some time to bring up the ppp interface
sleep 2

# Route the target IP range through the tunnel
tunnel_ip=$(ip addr show $TUNNEL_INTERFACE | grep "inet\b" | awk '{print $2}')
ip route add "$TARGET_IP_RANGE" via "$tunnel_ip"
