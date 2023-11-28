#!/bin/bash

while getopts ":o:t:p:u:n:l:g:" opt; do
  case $opt in
  p)
    DESTINATION="$OPTARG"
    ;;
  o)
    ORGANIZATION_NAME="$OPTARG"
    ;;
  t)
    TOKEN="$OPTARG"
    ;;
  u)
    RUN_AS="$OPTARG"
    ;;
  n)
    NAME="$OPTARG"
    ;;
  l)
    LABELS="$OPTARG"
    ;;
  g)
    GROUP="$OPTARG"
    ;;
  \?)
    echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

if [ -z "$ORGANIZATION_NAME" ]; then
  echo "Organization name is required"
  exit 1
fi

if [ -z "$TOKEN" ]; then
  echo "PAT Token is required"
  exit 1
fi

if [ -z "$DESTINATION" ]; then
  DESTINATION="$HOME/actions-runner"
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
  echo "Creating a folder $DESTINATION/actions-runner"
  mkdir $DESTINATION/actions-runner
  cd $DESTINATION/actions-runner
  # Get the latest version of the GitHub Actions runner
  LATEST_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name')
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
  curl -s -o "actions-runner-linux-${ARCHITECTURE}-${LATEST_VERSION}.tar.gz" -L "https://github.com/actions/runner/releases/download/${LATEST_VERSION}/actions-runner-linux-${ARCHITECTURE}-${LASTEST_VERSION_SMALL}.tar.gz"
  
  echo "Extracting the latest version of the GitHub Actions runner"
  # Extract the installer
  tar xzf "./actions-runner-linux-${ARCHITECTURE}-${LATEST_VERSION}.tar.gz"
  rm "./actions-runner-linux-${ARCHITECTURE}-${LATEST_VERSION}.tar.gz"

  echo "Configuring permissions for the runner"  
  chown -R $RUN_AS:$RUN_AS $DESTINATION/actions-runner
}

function Configure {
  # Getting the registration token
  echo "Configuring the actions runner for $ORGANIZATION_NAME"
  AUTH_TOKEN=$(curl -s -L -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token $TOKEN" -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/orgs/$ORGANIZATION_NAME/actions/runners/registration-token | jq -r '.token')
  echo "Auth Token is $AUTH_TOKEN"

  # Create the runner and start the configuration experience
  echo "Configuring the runner as $RUN_AS"
  OPTIONS="--url https://github.com/$ORGANIZATION_NAME --token $AUTH_TOKEN"
  if [ -n "$LABELS" ]; then
    OPTIONS+=" --labels $LABELS"
  fi
  if [ -n "$NAME" ]; then
    OPTIONS+=" --name $NAME"
  fi
  if [ -n "$GROUP" ]; then
  echo "test"
    OPTIONS+=" --group $GROUP"
  fi
  sudo -u $RUN_AS  $DESTINATION/actions-runner/config.sh $OPTIONS --unattended

  # Creating a service file
  read -r -d '' SERVICE <<EOF
[Unit]
Description=GitHub Actions Runner
After=network.target

[Service]
Type=simple
User=$RUN_AS
WorkingDirectory=$DESTINATION
ExecStart=$DESTINATION/actions-runner/run.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  # Create a service file
  echo "$SERVICE" >$DESTINATION/actions-runner.service

  # Register the service
  sudo mv $DESTINATION/actions-runner.service /etc/systemd/system/actions-runner.service
  sudo systemctl enable actions-runner.service
}

function Start {
  # Start the service
  echo "Starting the service"
  sudo systemctl start actions-runner.service
}

Install
Configure
Start
echo "Done"