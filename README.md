# L2TP script

Recently I set up a L2TP/IPsec VPN on my Arch Linux machine and there were so many different config files to keep track of with IP addresses, user names, passwords, etc. scattered through them. There's no way I was going to remember how to set all that up and guides I used might go offline so... I wrote a script to do it for me next time.

## Requirements

* openswan
* xl2tpd

I wrote this for my Arch Linux machine so the script uses systemd to start these services and writes config files to where Arch keeps them.
