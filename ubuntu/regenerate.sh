#!/bin/bash

HOSTNAME=""
REBOOT="false"
while getopts "hr" opt; do
  case $opt in
  h)
    HOSTNAME="$OPTARG"
    ;;
  r)
    REBOOT="true"
    ;;
  \?)
    echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

function get_os {
  case "$OSTYPE" in
  linux*) echo "linux" ;;
  darwin*) echo "mac" ;;
  win*) echo "windows" ;;
  msys*) echo "windows" ;;
  cygwin*) echo "windows" ;;
  bsd*) echo "bsd" ;;
  solaris*) echo "solaris" ;;
  *) echo "unknown" ;;
  esac
}

function generate_random_hostname {
  echo "ubuntu-$(
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13
    echo ''
  )"
}

function renew_id {
  echo "Renewing the Machine ID"
  if [ -f /etc/machine-id ]; then
    rm /etc/machine-id
    systemd-machine-id-setup
    echo "Machine ID has been renewed to $(cat /etc/machine-id)"
  fi
}

function renew_hostname {
  echo "Renewing the hostname"
  if [ -f /etc/hostname ]; then
    echo "$1" >/etc/hostname
    hostnamectl set-hostname "$1"
    echo "Hostname has been renewed to $(hostname)"
  fi
}

# Check if the script is running as root (sudo), if not, exit
if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

OS=$(get_os)
if [ "$OS" != "linux" ]; then
  echo "This script is only compatible with Linux, exiting"
  exit 1
fi

renew_id
if [ -z "$HOSTNAME" ]; then
  renew_hostname "$(generate_random_hostname)"
else
  renew_hostname "$HOSTNAME"
fi

if [ "$REBOOT" == "true" ]; then
  echo "Rebooting the system"
  reboot
fi