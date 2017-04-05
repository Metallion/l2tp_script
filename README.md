# L2TP script

Recently I set up a L2TP/IPsec VPN on my Arch Linux machine and there were so many different config files to keep track of with IP addresses, user names, passwords, etc. scattered through them. There's no way I was going to remember how to set all that up and guides I used might go offline so... I wrote a script to do it for me next time.

## Usage

Set the following environment variables to match the L2TP/IPSec VPN that you're connecting to.

`TARGET_IP_RANGE` means a CIDR notation of the destination IP range you wish to route through the VPN tunnel.
The rest should be self explanatory.

You can also put these in another file and pass that as an argument.

* L2TP_SERVER_IP
* L2TP_USER_NAME
* L2TP_PASSWORD
* IPSEC_PRE_SHARED_KEY
* TARGET_IP_RANGE

## Requirements

* openswan
* xl2tpd

I wrote this for my Arch Linux machine so the script uses systemd to start these services and writes config files to where Arch keeps them.
