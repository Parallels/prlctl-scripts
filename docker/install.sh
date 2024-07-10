#!/bin/bash

#!/bin/bash

# Gettting arguments
MODE="INSTALL"
while getopts "iu" opt; do
  case $opt in
  i)
    MODE="INSTALL"
    ;;
  u)
    MODE="UNINSTALL"
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

function enable_amd64_architecture {
  dpkg --add-architecture amd64
  apt-get update
}

function disable_amd64_architecture {
  dpkg --remove-architecture amd64
  apt-get update
}

function enable_amd64_sources_2204 {
  echo "Enabling amd64 sources for Ubuntu 22.04"
  sed -i 's/^deb http/deb [arch=arm64] http/' /etc/apt/sources.list
  sed -i 's/^deb-src http/deb-src [arch=arm64] http/' /etc/apt/sources.list

  cmd1="deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ $(get_linux_distro_codename) main restricted universe multiverse"
  cmd2="deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ $(get_linux_distro_codename)-updates main restricted universe multiverse"
  cmd3="deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ $(get_linux_distro_codename)-backports main restricted universe multiverse"
  cmd4="deb [arch=amd64] http://security.ubuntu.com/ubuntu/ $(get_linux_distro_codename)-security main restricted universe multiverse"
  {
    echo "$cmd1"
    echo "$cmd2"
    echo "$cmd3"
    echo "$cmd4"
  } >>/etc/apt/sources.list
}

function disable_amd64_sources_2204 {
  echo "Disabling amd64 sources for Ubuntu 22.04"
  sed -i 's/deb \[arch=arm64\] http/deb http/' /etc/apt/sources.list
  sed -i 's/deb-src \[arch=arm64\] http/deb-src http/' /etc/apt/sources.list
  sed -i '/^deb \[arch=amd64\]/d' /etc/apt/sources.list
}

function enable_amd64_sources_2404 {
  echo "Enabling amd64 sources for Ubuntu 24.04"
  CONTENT=$(
    cat <<EOF
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Architectures: arm64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports/
Suites: noble-security
Components: main restricted universe multiverse
Architectures: arm64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Architectures: amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: noble-security
Components: main restricted universe multiverse
Architectures: amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

EOF
  )
  cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
  echo "$CONTENT" >/etc/apt/sources.list.d/ubuntu.sources
}

function disable_amd64_sources_2404 {
  echo "Disabling amd64 sources for Ubuntu 24.04"
  rm /etc/apt/sources.list.d/ubuntu.sources
  mv /etc/apt/sources.list.d/ubuntu.sources.bak /etc/apt/sources.list.d/ubuntu.sources
}

function install_docker {
  echo "Installing Docker"
  apt-get update
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /usr/share/keyrings/docker.gpg
  chmod a+r /usr/share/keyrings/docker.gpg

  echo \
    "deb [signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  apt-get update

  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  echo "Docker has been installed"
}

function uninstall_docker {
  echo "Uninstalling Docker"
  apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  apt-get autoremove -y
  echo "Docker has been uninstalled"
}

function install_dependencies {
  echo "Installing dependencies"
  apt-get update
  apt-get install -y curl wget git jq ca-certificates apt-transport-https
  echo "Dependencies have been installed"
}

function uninstall_dependencies {
  echo "Uninstalling dependencies"
  apt-get purge -y curl git jq
  apt-get autoremove -y
  echo "Dependencies have been uninstalled"
}

function upgrade_system {
  echo "Upgrading the system"
  apt-get update
  apt-get upgrade -y
  echo "System has been upgraded"
}

function install {
  echo "- Detected OS: $OS"

  DISTRO="$(get_linux_distro)"

  echo "- Detected Disto: $DISTRO"

  if [ "$DISTRO" != "ubuntu" ]; then
    echo "This script is only compatible with Ubuntu, exiting"
    exit 1
  fi

  VERSION="$(get_linux_distro_version)"
  echo "- Detected Ubuntu version: $VERSION"

  if [ "$VERSION" == "24.04" ]; then
    enable_amd64_sources_2404
    enable_amd64_architecture
  elif [ "$VERSION" == "22.04" ]; then
    enable_amd64_sources_2204
    enable_amd64_architecture
  else
    echo "This script is only compatible with Ubuntu 20.04 and 22.04, exiting"
    exit 1
  fi

  echo "Installing a new cluster"

  install_dependencies
  install_docker
}

function uninstall {
  echo "Detected OS: $OS"
  VERSION="$(get_linux_distro_version)"
  echo "Detected Ubuntu version: $VERSION"
  uninstall_docker

  if [ "$VERSION" == "24.04" ]; then
    disable_amd64_sources_2404
    disable_amd64_architecture
  elif [ "$VERSION" == "22.04" ]; then
    disable_amd64_sources_2204
    disable_amd64_architecture
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

if [ -z "$MODE" ]; then
  echo "Choose either install or uninstall mode"
  exit 1
fi

if [ "$MODE" == "INSTALL" ]; then
  install
fi

if [ "$MODE" == "UNINSTALL" ]; then
  uninstall
fi
