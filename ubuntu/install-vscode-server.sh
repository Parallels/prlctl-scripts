#!/bin/bash

# Gettting arguments
MODE="INSTALL"
ENABLE_SERVICE="false"
TUNNEL_NAME="code-server"
while [[ $# -gt 0 ]]; do
  case $1 in
  -i)
    MODE="INSTALL"
    shift # past argument
    ;;
  -u)
    echo "Uninstalling Visual Studio Code"
    MODE="UNINSTALL"
    shift # past argument
    ;;
  --enable-tunnel)
    ENABLE_SERVICE="true"
    shift # past argument
    ;;
  --name)
    TUNNEL_NAME=$2
    shift # past argument
    shift # past argument
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

function get_linux_distro {
  DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  echo "$DISTRO"
}

function get_linux_distro_version {
  DISTRO_VERSION=$(lsb_release -sr | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  echo "$DISTRO_VERSION"
}

function get_linux_distro_codename {
  DISTRO_CODENAME=$(lsb_release -sc | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  echo "$DISTRO_CODENAME"
}

install_service() {
  code tunnel service install  --accept-server-license-terms --name $TUNNEL_NAME
  sudo loginctl enable-linger $USER
}

function install() {
  echo "Installing Visual Studio Code"
  if command -v code &>/dev/null; then
    echo "Visual Studio Code is already installed, skipping installation"
    return
  fi

  DEBIAN_FRONTEND=noninteractive sudo apt install curl gpg
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --yes -o /usr/share/keyrings/packages.microsoft.gpg
  sudo chmod a+r /usr/share/keyrings/packages.microsoft.gpg

  echo \
    "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" |
    sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  rm -f packages.microsoft.gpg
  DEBIAN_FRONTEND=noninteractive sudo apt install -y apt-transport-https
  sudo apt update
  DEBIAN_FRONTEND=noninteractive sudo apt install -y code
  DEBIAN_FRONTEND=noninteractive sudo apt autoremove -y
}

function login() {
  code tunnel user login
}

function uninstall() {
  echo "Uninstalling Visual Studio Code"
  if command -v code &>/dev/null; then
    code tunnel service uninstall
    sudo apt remove -y code
    sudo apt autoremove -y
  fi

  sudo rm -f /etc/apt/keyrings/packages.microsoft.gpg
  sudo rm -f /etc/apt/sources.list.d/vscode.list
  sudo rm -f /usr/share/keyrings/packages.microsoft.gpg
  sudo rm -rf /home/$USER/.vscode

  echo "Visual Studio Code has been uninstalled"
}

function install_devtunnel_cli() {
  curl -sL https://aka.ms/DevTunnelCliInstall | bash
}

function check_for_vscode() {
  if ! command -v code &>/dev/null; then
    return 1
  else
    return 0
  fi
}

OS=$(get_os)
if [ "$OS" != "linux" ]; then
  echo "This script is only compatible with Linux, exiting"
  exit 1
fi

if [ -z "$MODE" ]; then
  echo "Choose either install or uninstall mode"
  exit 1
fi

if [ "$MODE" == "INSTALL" ]; then
  if ! check_for_vscode; then
    echo "Visual Studio Code is not installed, installing"
    install
    install_devtunnel_cli
  else
    echo "Visual Studio Code is already installed, skipping installation"
  fi

  if [ "$ENABLE_SERVICE" = "true" ]; then
    login
    install_service
  fi
fi

if [ "$MODE" == "UNINSTALL" ]; then
  if check_for_vscode; then
    uninstall
  else
    echo "Visual Studio Code is not installed, skipping uninstallation"
  fi
fi
