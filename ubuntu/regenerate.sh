#!/bin/bash

MODE="REGENERATE_ALL"
HOSTNAME=""
REBOOT="false"

while [[ $# -gt 0 ]]; do
  case $1 in
  --regenerate)
    MODE="REGENERATE_ALL"
    shift
    ;;
  --regenerate-id)
    MODE="REGENERATE_ID"
    shift
    ;;
  --regenerate-hostname)
    MODE="REGENERATE_HOSTNAME"
    shift
    ;;
  --upgrade)
    MODE="UPGRADE"
    shift
    ;;
  --get-os)
    MODE="GET_OS"
    ;;
  --hostname)
    HOSTNAME=$2
    shift
    shift
    ;;
  -reboot)
    REBOOT="true"
    shift
    ;;
  *)
    echo "Invalid option $1" >&2
    exit 1
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

function upgrade_system {
  echo "Upgrading the system"
  apt-get update
  apt-get upgrade -y
  echo "System has been upgraded"
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

if [ "$MODE" == "REGENERATE_ALL" ]; then
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
elif [ "$MODE" == "REGENERATE_ID" ]; then
  renew_id
  if [ "$REBOOT" == "true" ]; then
    echo "Rebooting the system"
    reboot
  fi
elif [ "$MODE" == "REGENERATE_HOSTNAME" ]; then
  if [ -z "$HOSTNAME" ]; then
    renew_hostname "$(generate_random_hostname)"
  else
    renew_hostname "$HOSTNAME"
  fi
elif [ "$MODE" == "UPGRADE" ]; then
  upgrade_system
elif [ "$MODE" == "GET_OS" ]; then
  get_os
fi
