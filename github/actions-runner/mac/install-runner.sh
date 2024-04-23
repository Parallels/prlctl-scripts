#!/bin/bash

while getopts ":o:t:p:u:n:l:g:" opt; do
  case $opt in
  p)
    DESTINATION="$OPTARG"
    ;;
  u)
    RUN_AS="$OPTARG"
    ;;
  \?)
    echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

if [ -z "$DESTINATION" ]; then
  echo "Setting the destination to $HOME"
  DESTINATION="$HOME"
fi

if [ -z "$RUN_AS" ]; then
  RUN_AS=$USER
fi

if [ -z "$NAME" ]; then
  NAME=$(hostname)
fi

function Install {
  echo "Getting the latest version of the GitHub Actions runner"
  # Create a folder
  echo "Creating a folder $DESTINATION/action-runner"
  mkdir $DESTINATION/action-runner
  cd $DESTINATION/action-runner
  # Get the latest version of the GitHub Actions runner
  LATEST_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p')
  LASTEST_VERSION_SMALL=$(echo $LATEST_VERSION | sed 's/v//g')

  # Get the architecture and define some common names
  ARCHITECTURE=$(uname -m)
  if [ "$ARCHITECTURE" == "x86_64" ]; then
    ARCHITECTURE="x64"
  fi
  if [ "$ARCHITECTURE" == "aarch64" ]; then
    ARCHITECTURE="arm64"
  fi

  LABELS+=",$ARCHITECTURE"

  echo "Latest version is $LATEST_VERSION for architecture $ARCHITECTURE"

  echo "Downloading the latest version of the GitHub Actions runner"
  # Download the latest runner package
  curl -s -o "actions-runner-osx-${ARCHITECTURE}-${LATEST_VERSION}.tar.gz" -L "https://github.com/actions/runner/releases/download/${LATEST_VERSION}/actions-runner-osx-${ARCHITECTURE}-${LASTEST_VERSION_SMALL}.tar.gz"

  echo "Extracting the latest version of the GitHub Actions runner"
  # Extract the installer
  tar xzf "./actions-runner-osx-${ARCHITECTURE}-${LATEST_VERSION}.tar.gz"
  if [ $? -ne 0 ]; then
    echo "Failed extract the runner"
    exit 1
  fi
  rm "./actions-runner-osx-${ARCHITECTURE}-${LATEST_VERSION}.tar.gz"

  echo "Configuring permissions for the runner"
  chown -R $RUN_AS $DESTINATION/action-runner
}

echo "Installing the GitHub Actions runner into $DESTINATION as $RUN_AS"

Install
echo "Done"
