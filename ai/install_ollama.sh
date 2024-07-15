#!/bin/bash

# Gettting arguments
MODE="INSTALL"
ENABLE_UI=false
UI_PORT=8080
DEFAULT_MODEL="phi3:mini"
PULL_MODEL=""
while [[ $# -gt 0 ]]; do
  case $1 in
  -i)
    MODE="INSTALL"
    shift # past argument
    ;;
  -u)
    MODE="UNINSTALL"
    shift # past argument
    ;;
  -p)
    MODE="PULL"
    shift # past argument
    ;;
  --enable-ui)
    ENABLE_UI=true
    shift # past argument
    ;;
  --ui-port)
    UI_PORT=$2
    shift # past argument
    shift # past value
    ;;
  --model)
    PULL_MODEL=$2
    shift # past argument
    shift # past value
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

function install_docker {
  echo "Installing Docker"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Parallels/prlctl-scripts/main/docker/install.sh)" - -i
}

function uninstall_docker {
  echo "Uninstalling Docker"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Parallels/prlctl-scripts/main/docker/install.sh)" - -u
}

function check_for_docker {
  if ! command -v docker &>/dev/null; then
    return 1
  else
    return 0
  fi
}

function install_ollama {
  echo "Installing Ollama"
  if ! check_for_ollama; then
    /bin/bash -c "$(curl -fsSL https://ollama.com/install.sh)"
  else
    echo "Ollama is already installed, skipping installation"
  fi
  
  # mkdir /usr/share/ollama
  # chown ollama:ollama /usr/share/ollama
  # chmod 755 /usr/share/ollama
  setup_service

  sudo systemctl start ollama
  echo "Waiting for Ollama to start"
  sleep 1

  if [ -z "$PULL_MODEL" ]; then
    pull_model "$DEFAULT_MODEL"
  else
    pull_model "$PULL_MODEL"
  fi
}
function check_for_ollama {
  if ! command -v ollama &>/dev/null; then
    return 1
  else
    return 0
  fi
}

function setup_service {
  echo "Enabling Ollama API"
  sudo systemctl stop ollama
  sudo sed -i '/^Environment=/a Environment="OLLAMA_HOST=0.0.0.0"' /etc/systemd/system/ollama.service
  # sed -i '/^Environment=/a Environment="OLLAMA_MODELS=/mnt/ollama_models"' /etc/systemd/system/ollama.service
  sudo systemctl daemon-reload
  sudo systemctl start ollama
}

function pull_model {
  echo "Pulling model $1"
  ollama pull "$1"
}

function uninstall_ollama {
  echo "Uninstalling Ollama"
  sudo systemctl stop ollama
  sudo systemctl disable ollama
  rm /etc/systemd/system/ollama.service
  rm "$(which ollama)"
  rm -r /usr/share/ollama

  sudo userdel ollama
  sudo groupdel ollama
}

function install {
  install_ollama
  if [ "$ENABLE_UI" = true ]; then
    echo "Enabling Ollama UI"
    if check_for_docker; then
      echo "Docker is already installed, skipping installation"
    else
      install_docker
    fi

    sudo docker run -d -p "$UI_PORT":8080 --add-host=host.docker.internal:host-gateway -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:main
  fi
}

function uninstall {
  uninstall_ollama

  if ! check_for_docker; then
    echo "Docker is not installed, skipping uninstallation"
    return
  fi
  sudo docker stop open-webui
  sudo docker rm open-webui --force
  uninstall_docker
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
  install
fi

if [ "$MODE" == "UNINSTALL" ]; then
  uninstall
fi

if [ "$MODE" == "pull" ]; then
  if [ -z "$PULL_MODEL" ]; then
    echo "Please provide a model name"
    exit 1
  fi

  pull_model "$PULL_MODEL"
fi
