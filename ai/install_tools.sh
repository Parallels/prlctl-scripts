#!/bin/bash

# Gettting arguments
MODE="INSTALL"
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
  *)
    echo "Invalid option $1" >&2
    exit 1
    ;;
  esac
done

function generate_requirements() {
  content="fastapi==0.111.0
uvicorn[standard]==0.22.0
pydantic==2.7.1
python-multipart==0.0.9

Flask==3.0.3
Flask-Cors==4.0.1

python-socketio==5.11.3
python-jose==3.3.0
passlib[bcrypt]==1.7.4

requests==2.32.3
aiohttp==3.9.5
sqlalchemy==2.0.30
alembic==1.13.2
peewee==3.17.6
peewee-migrate==1.12.2
psycopg2-binary==2.9.9
PyMySQL==1.1.1
bcrypt==4.1.3
SQLAlchemy
pymongo
redis
boto3==1.34.110

argon2-cffi==23.1.0
APScheduler==3.10.4

# AI libraries
openai
anthropic
google-generativeai==0.5.4
tiktoken

langchain==0.2.6
langchain-community==0.2.6
langchain-chroma==0.1.2

fake-useragent==1.5.1
chromadb==0.5.3
sentence-transformers==3.0.1
pypdf==4.2.0
docx2txt==0.8
python-pptx==0.6.23
unstructured==0.14.9
Markdown==3.6
pypandoc==1.13
pandas==2.2.2
openpyxl==3.1.5
pyxlsb==1.0.10
xlrd==2.0.1
validators==0.28.1
psutil

opencv-python-headless==4.10.0.84
rapidocr-onnxruntime==1.3.22

fpdf2==2.7.9
rank-bm25==0.2.2

faster-whisper==1.0.2

PyJWT[crypto]==2.8.0
authlib==1.3.1

black==24.4.2
langfuse==2.38.0
youtube-transcript-api==0.6.2
pytube==15.0.0

extract_msg
pydub
duckduckgo-search~=6.1.7

## Tests
docker~=7.1.0
pytest~=8.2.2
pytest-docker~=3.1.1"

  echo "$content" >requirements.txt
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

function install() {
  echo "Installing AI toolset"

  sudo apt update
  sudo apt install -y  --no-install-recommends pandoc netcat-openbsd curl jq gcc cmake
  sudo apt install -y  --no-install-recommends python3-pip python3-venv
  sudo apt install -y  --no-install-recommends ffmpeg libsm6 libxext6
  sudo apt install -y libhdf5-dev cython3

  echo "Creating virtual environment"
  current_folder=$(pwd)
  if [ ! -d "$HOME"/.python_env ]; then
    mkdir "$HOME"/.python_env
  fi

  cd "$HOME"/.python_env || exit
  python3 -m venv python_env

  generate_requirements

  source /home/$USER/.python_env/env/bin/activate
  pip3 install --upgrade pip

  pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --no-cache-dir
  pip3 install ftfy regex requests pandas seaborn facesudo 
  pip3 install opencv-python pycocotools tensorflow --no-cache-dir

  pip3 install  -r requirements.txt --no-cache-dir

  echo "source /home/$USER/.python_env/env/bin/activate" >> ~/.bashrc

  cd "$current_folder" || exit
}

function uninstall() {
  echo "Uninstalling AI toolset"

  pip3 uninstall torch -y

  sudo apt remove -y pandoc netcat-openbsd curl jq gcc python3-pip python3-venv ffmpeg libsm6 libxext6

  sudo apt autoremove -y
  rm -rf "$HOME"/.pytorch_env

  echo "Uninstall complete"
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