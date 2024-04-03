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
    echo "Failed configure the runner"
    exit 1
  fi

  # Creating a service file
  read -r -d '' SERVICE <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>UserName</key>
    <string>$RUN_AS</string>
    <key>Label</key>
    <string>com.github.actions-runner</string>
    <key>ProgramArguments</key>
    <array>
      <string>$DESTINATION/actions-runner/run.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/actions-runner.err</string>
    <key>StandardOutPath</key>
    <string>/tmp/actions-runner.out</string> 
  </dict>
</plist>
EOF

  # Create a service file
  echo "$SERVICE" >$DESTINATION/com.github.actions-runner.plist

  # Register the service
  sudo mv $DESTINATION/com.github.actions-runner.plist /Library/LaunchDaemons/com.github.actions-runner.plist
  sudo chown root:wheel /Library/LaunchDaemons/com.github.actions-runner.plist
  sudo chmod 644 /Library/LaunchDaemons/com.github.actions-runner.plist
}

function Start {
  # Start the service
  echo "Starting the service"
  sudo launchctl load /Library/LaunchDaemons/com.github.actions-runner.plist
  if [ $? -ne 0 ]; then
    echo "Failed to start the runner"
    exit 1
  fi
}

Configure
Start
echo "Done"
