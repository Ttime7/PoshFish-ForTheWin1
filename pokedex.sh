#!/bin/bash
################################################################################
# Written by: K7-Avenger, previous & current MetroCCDC team member(s)          #
# For: Metro State CCDC 2023-2024                                              #
# Purpose: To set appropriate firewall (iptables) rules for linux hosts and    #
# add logging rules which may indicate a particular host is activly under      #
# attack.                                                                      #
################################################################################

# This section is used to define colors used to improve readability of output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Sets the default policies to "allow-listing"
# Allows connections via the loopback adapter
# Allows inbound connections only if they were started by the host
defaultPolicy(){
  iptables --policy INPUT DROP
  iptables --policy FORWARD DROP
  iptables --policy OUTPUT DROP
  iptables -A INPUT -i lo -j ACCEPT
  iptables -A OUTPUT -o lo -j ACCEPT
  iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
}

logFirewallEvents(){
  iptables -A INPUT -m limit --limit 2/min -j LOG --log-prefix "Input-Dropped: " --log-level 4
  iptables -A FORWARD -m limit --limit 2/min -j LOG --log-prefix "Forward-Dropped: " --log-level 4
  iptables -A OUTPUT -m limit --limit 2/min -j LOG --log-prefix "Output-Dropped: " --log-level 4
  iptables -A INPUT -p tcp --tcp-flags ALL NONE -m limit --limit 1/min -j LOG --log-prefix "NULL packet: "
  iptables -A INPUT -p tcp --tcp-flags ALL ALL -m limit --limit 1/min -j LOG --log-prefix "XMAS packet: "
  iptables -A INPUT -f -m limit --limit 1/min -j LOG --log-prefix "Fragmented packet: "
  iptables -A INPUT -p tcp ! --syn -m state --state NEW -m limit --limit 1/min -j LOG --log-prefix "SYN packet flood: "
  iptables -A INPUT -p icmp -m limit --limit 1/minute -j LOG --log-prefix "ICMP Flood: "
  iptables -A FORWARD -f -m limit --limit 1/min -j LOG --log-prefix "Hacked Client "
}

# Allow web browsing
allowWebBrowsing(){
  iptables -A OUTPUT -p tcp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A OUTPUT -p udp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 80 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A OUTPUT -p udp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
}

# Rule for a DNS/NTP clients
allowDNSNTPclient(){
  iptables -A OUTPUT -p tcp --dport 53 -d -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A OUTPUT -p udp --dport 53 -d -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A OUTPUT -p udp --dport 123 -d -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
}

# Rules for HIDS clients
allowHIDSClient(){
  iptables -A OUTPUT -p tcp --dport 1514 -d $1 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT  #Agent connection
  iptables -A OUTPUT -p udp --dport 1514 -d $1 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT  #Agent connection
  iptables -A OUTPUT -p tcp --dport 1515 -d $1 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT  #Agent enrollment
  iptables -A OUTPUT -p tcp --dport 514 -d $1 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT  #Syslog collector
  iptables -A OUTPUT -p udp --dport 514 -d $1 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT  #Syslog collector
}

# Rule for a syslog clients
allowSysLog(){
  read -p "Enter IP address for Splunk server" sip
  iptables -A OUTPUT -p tcp --dport 9997 -d $sip -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 9998 -d $sip -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 601 -d $sip -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A OUTPUT -p udp --dport 514 -d $sip -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
}

allowICMP(){
  iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
  iptables -A OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT
}

flushFirewall(){
  iptables -F
  iptables --policy INPUT ACCEPT
  iptables --policy FORWARD ACCEPT
  iptables --policy OUTPUT ACCEPT
  echo -e -n "${RED}"
  echo "Firewall rules removed, user beware!"
  echo -e "${RESET}"
}

showFirewall(){
  echo -e -n "${GREEN}"
  echo -e "...DONE"
  echo -e -n "${CYAN}"
  iptables -L --line-numbers
  echo -e "${RESET}"
}

setDNS-NTP(){
  flushFirewall  #Removes any potentially bad rules
  logFirewallEvents
  defaultPolicy
  allowWebBrowsing
  allowICMP
  allowSysLog 
  # Rules for DNS/NTP server
  iptables -A INPUT -p tcp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A INPUT -p tcp --dport 953 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A INPUT -p udp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A INPUT -p udp --dport 953 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A OUTPUT -p tcp --sport 53 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A OUTPUT -p tcp --sport 953 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A OUTPUT -p udp --sport 53 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A OUTPUT -p udp --sport 953 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -A INPUT -p udp --dport 123 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
  iptables -A OUTPUT -p udp --sport 123 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  
  # Rules for DNS/NTP client of upstream provider(s)
  iptables -A OUTPUT -p tcp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 953 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
  iptables -A OUTPUT -p udp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
  iptables -A OUTPUT -p udp --dport 953 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
  iptables -A OUTPUT -p udp --dport 123 -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
  showFirewall  
}

setSplunk(){
  flushFirewall  #Removes any potentially bad rules
  defaultPolicy
  allowWebBrowsing
  allowICMP
  allowSysLog 
  allowDNSNTPclient
  
  # Splunk WebGUI rules 
  iptables -A INPUT -p tcp --dport 8000 -j ACCEPT
  iptables -A OUTPUT -p tcp --sport 8000 -j ACCEPT

  # Splunk Management Port
  iptables -A INPUT -p tcp --dport 8089 -j ACCEPT

  # Syslog traffic
  iptables -A INPUT -p tcp --dport 9997 -j ACCEPT
  iptables -A INPUT -p tcp --dport 9998 -j ACCEPT
  iptables -A INPUT -p tcp --dport 601 -j ACCEPT
  iptables -A INPUT -p udp --dport 514 -j ACCEPT
  
  allowSysLog
  dropall
  showFirewall
}

while getopts 'dfijs :' OPTION; do
  case "$OPTION" in
    d)
      echo "Appling firewall rules for DNS-NTP..."
      defaultPolicy
      allowWebBrowsing
      setDNS-NTP
      ;;
    f)
      echo "Removing all firewall rules..."
      flushFirewall
      echo -e -n "${RED}"
      iptables -L
      echo "Firewall rules removed, default policy set to ACCEPT user beware!"
      echo -e "${RESET}"
      ;;
    i)
      read -p "Enter IP address for HIDS server" hip
      echo "Applying firewall rules for HIDS clients"
      allowHIDSClient $hip
      ;;
    j)
      read -p "Enter network IP address for HIDS clients" hip
      echo "Applying firewall rules for HIDS server"
      allowHIDSserver $hip
      ;;
    s)
      echo "Applying secure firewall rules..."
      defaultPolicy
      allowWebBrowsing
      showFirewall
      ;;
    ?)
      echo -e -n "${YELLOW}"
      echo -e "Correct usage:\t $(basename $0) -flag(s)"
      echo -e "-d\t Applies firewall rules for DNS/NTP"
      echo -e "-f\t Deletes all firewall rules"
      echo -e "-i\t Applies firewall rules for HIDS clients"
      echo -e "-j\t Applies firewall rules for HIDS server"
      echo -e "-h\t or any unlisted flag returns this message."
      echo -e "${RESET}"
      exit 1
      ;;
  esac
done
