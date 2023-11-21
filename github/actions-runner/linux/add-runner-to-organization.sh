#!/bin/bash

while getopts ":o:t:p:" opt; do
  case $opt in
    p) PATH="$OPTARG"
    ;;
    o) ORGANIZATION_NAME="$OPTARG"
    ;;
    t) TOKEN="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

if [ -z "$ORGANIZATION_NAME" ]; then
  echo "Organization name is required"
  exit 1
fi

if [ -z "$TOKEN" ]; then
  echo "Token is required"
  exit 1
fi

# Create the runner and start the configuration experience
~/actions-runner/config.sh --url https://github.com/$ORGANIZATION_NAME --token $TOKEN --labels macos --unattended
# Last step, run it!
~/actions-runner/run.sh &