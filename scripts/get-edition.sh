#!/bin/bash

############
# Get the edition of the Parallels Server
#
# This script will get the edition of the Parallels Server
#
############

function get_license_state() {
  is_installed=$(which prlsrvctl)
  if [[ $is_installed ]]; then
    license_output=$(prlsrvctl info | grep "License:")

    if [[ -n "$license_output" ]]; then
      license_state=$(echo "$license_output" | awk -F "state='" '{print $2}' | awk -F "'" '{print $1}')

      if [[ "$license_state" != "valid" ]]; then
        echo "Invalid License"
        exit 1
      fi
    else
      echo "No License found"
      exit 1
    fi
  else
    echo "Parallels is not installed"
    exit 1
  fi
}

get_license_state

edition=$(prlsrvctl info --license | awk -F '=' '/edition/ {gsub(/"/, "", $2); print $2}')
if [[ $edition ]]; then
  echo "$edition"
else
  echo "No Edition found"
  exit 1
fi
exit 0
