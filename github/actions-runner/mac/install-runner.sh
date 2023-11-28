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
  sudo mkdir $DESTINATION/actions-runner
  cd $DESTINATION/actions-runner
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
  rm "./actions-runner-osx-${ARCHITECTURE}-${LATEST_VERSION}.tar.gz"

  echo "Configuring permissions for the runner"  
  sudo chown -R $RUN_AS $DESTINATION/actions-runner
}

function Configure {
  # Getting the registration token
  echo "Configuring the actions runner for $ORGANIZATION_NAME"
  AUTH_TOKEN=$(curl -s -L -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token $TOKEN" -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/orgs/$ORGANIZATION_NAME/actions/runners/registration-token | sed -n 's/.*"token": "\([^"]*\)".*/\1/p')
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
    <string>/tmp/acions-runner.out</string> 
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
}

Install
Configure
Start
echo "Done"