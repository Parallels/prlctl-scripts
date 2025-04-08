#!/bin/bash

############
# Get the version of the Parallels Server
#
# This script will get the version of the Parallels Desktop
#
############

function get_license_state() {
  is_installed=$(which prlsrvctl)
  if [[ $is_installed ]]; then
    license_output=$(prlsrvctl info | grep "License:")

    if [[ -n "$license_output" ]]; then
      license_state=$(echo "$license_output" | awk -F "state='" '{print $2}' | awk -F "'" '{print $1}')

      if [[ "$license_state" != "valid" ]]; then
        echo "$license_state"
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

info=$(prlsrvctl info | awk -F ': ' '/^Version/ {print $2}')

if [[ $info ]]; then
  ##if info is present, return that
  echo "$info"

else
  ##if no info is present, return "Not Installed"
  echo "Not Installed"
fi

exit 0
