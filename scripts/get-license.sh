#!/bin/bash

############
# Get the license of the Parallels Server
#
# This script will get the license of the Parallels Server
#
############

is_installed=$(which prlsrvctl)

if [[ $is_installed ]]; then
  license_output=$(prlsrvctl info | grep "License:")

  if [[ -n "$license_output" ]]; then
    license_state=$(echo "$license_output" | awk -F "state='" '{print $2}' | awk -F "'" '{print $1}')
    license_key=$(echo "$license_output" | awk -F "key='" '{print $2}' | awk -F "'" '{print $1}')

    if [[ "$license_state" == "valid" ]]; then
      echo "$license_key"
    else
      echo "Invalid License"
    fi
  else
    echo "No License found"
  fi
else
  echo "Parallels is not installed"
  exit 1
fi

exit 0
