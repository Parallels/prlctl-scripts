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

function Configure {
  # Getting the registration token
  echo "Configuring the actions runner for $ORGANIZATION_NAME"
  URL_PATH="orgs/$ORGANIZATION_NAME"
  if [[ $ORGANIZATION_NAME == *"/"* ]]; then
    echo "This seems to be a request for a repository runner"
    URL_PATH="repos/$ORGANIZATION_NAME"
  fi

  # Rest of the code...
  AUTH_TOKEN=$(curl -s -L -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token $TOKEN" -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/$URL_PATH/actions/runners/registration-token | sed -n 's/.*"token": "\([^"]*\)".*/\1/p')
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
  sudo -u $RUN_AS $DESTINATION/actions-runner/config.sh $OPTIONS --unattended
  if [ $? -ne 0 ]; then
    echo "Failed to configure the runner"
    exit 1
  fi

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
  if [ $? -ne 0 ]; then
    echo "Failed to start the runner"
    exit 1
  fi
}

Configure
Start
echo "Done"
