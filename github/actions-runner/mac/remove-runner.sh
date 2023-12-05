#!/bin/bash

while getopts ":o:t:p:u:" opt; do
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

function Remove() {
    # Getting the registration token
  echo "Removing the actions runner from $ORGANIZATION_NAME"
  AUTH_TOKEN=$(curl -s -L -X POST -H "Accept: application/vnd.github+json" -H "Authorization: token $TOKEN" -H "X-GitHub-Api-Version: 2022-11-28" https://api.github.com/orgs/$ORGANIZATION_NAME/actions/runners/registration-token | sed -n 's/.*"token": "\([^"]*\)".*/\1/p')
  echo "Auth Token is $AUTH_TOKEN"

  sudo -u $RUN_AS $DESTINATION/actions-runner/config.sh remove --token $AUTH_TOKEN
    if $? -ne 0; then
    echo "Failed to remove the runner"
    exit 1
  fi
}

function Cleanup() {
  echo "Cleaning up the installation"
  sudo rm -rf $DESTINATION/actions-runner

  echo "Removing the service"
  sudo launchctl unload /Library/LaunchDaemons/com.github.actions-runner.plist
    if $? -ne 0; then
    echo "Failed to unload the runner service"
    exit 1
  fi
  sudo rm -f /Library/LaunchDaemons/com.github.actions-runner.plist
}

Remove
Cleanup
echo "Done"