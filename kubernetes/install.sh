#!/bin/bash

#gettting arguments
while getopts "igncj:" opt; do
  case $opt in
  j)
    echo "Joining cluster $OPTARG"
    JOIN=$OPTARG
    ;;
  i)
    echo "here"
    MODE="INSTALL"
    ;;
  g)
    MODE="GET_TOKEN"
    ;;
  c)
    MODE="GET_CONFIG"
    ;;
  n)
    MODE="GET_NODES"
    ;;
  \?)
    echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

function generate_random_hostname {
  echo "node-$(
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13
    echo ''
  )"
}

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

function enable_amd64_sources_2204 {
  cmd1="deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ $(get_linux_distro_codename) main restricted universe multiverse"
  cmd2="deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ $(get_linux_distro_codename)-updates main restricted universe multiverse"
  cmd3="deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ $(get_linux_distro_codename)-backports main restricted universe multiverse"
  cmd4="deb [arch=amd64] http://security.ubuntu.com/ubuntu/ $(get_linux_distro_codename)-security main restricted universe multiverse"
  {
    $cmd1
    $cmd2
    $cmd3
    $cmd4
  } >>/etc/apt/sources.list
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
  echo "$CONTENT" >/etc/apt/sources.list.d/ubuntu.sources
}

function install_helm {
  echo "Installing Helm"
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
  chmod 700 get_helm.sh
  ./get_helm.sh
  rm get_helm.sh
  echo "Helm has been installed"
}

function install_docker {
  echo "Installing Docker"
  apt-get update
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /usr/share/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.asc

  echo \
    "deb [arch=amd64 signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  apt-get update

  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  echo "Docker has been installed"
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

function install_kubectl {
  echo "Installing kubectl"
  curl -LO "https://dl.k8s.io/release/v1.21.0/bin/linux/amd64/kubectl"
  chmod +x kubectl
  mv kubectl /usr/local/bin/
  echo "kubectl has been installed"
}

function install_dependencies {
  echo "Installing dependencies"
  apt-get update
  apt-get install -y curl wget git jq ca-certificates apt-transport-https
  echo "Dependencies have been installed"
}

# installing micrk8s
function install_microk8s {
  echo "Installing microk8s"
  apt-get install -y snapd
  snap install microk8s --classic
  echo "microk8s has been installed, checking status"
  microk8s status --wait-ready
}

function get_join_token {
  output=$(microk8s add-node)
  second_line=$(echo "$output" | sed -n '2p')
  modified_line="${second_line#*join }" # Remove 'microk8s join' from the line

  echo "$modified_line"
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

if [ -z "$MODE" ] && [ -z "$JOIN" ]; then
  echo "Choose either to install or join a cluster"
  exit 1
fi

if [ "$MODE" == "INSTALL" ]; then
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

  renew_id
  renew_hostname "$(generate_random_hostname)"

  install_dependencies
  install_docker

  install_kubectl
  install_helm
  install_microk8s
elif [ "$MODE" == "GET_TOKEN" ]; then
  EXISTS=$(which microk8s)
  if [ -z "$EXISTS" ]; then
    echo "microk8s is not installed, exiting"
    exit 1
  fi

  get_join_token
elif [ "$MODE" == "GET_NODES" ]; then
  EXISTS=$(which microk8s)
  if [ -z "$EXISTS" ]; then
    echo "microk8s is not installed, exiting"
    exit 1
  fi

  microk8s kubectl get nodes
elif [ "$MODE" == "GET_CONFIG" ]; then
  EXISTS=$(which microk8s)
  if [ -z "$EXISTS" ]; then
    echo "microk8s is not installed, exiting"
    exit 1
  fi

  cat /var/snap/microk8s/current/credentials/client.config
fi

# if $JOIN is set, then join the cluster
if [ -n "$JOIN" ]; then
  echo "Joining an existing cluster $JOIN"
  microk8s join "$JOIN"
fi

if [ "$MODE" == "INSTALL" ]; then
  echo "Cluster has been installed"
  reboot
fi
