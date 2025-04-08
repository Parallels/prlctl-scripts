#!/bin/bash

############
# Get the number of virtual machines from the Parallels Desktop
#
# This script will get the number of virtual machines from the Parallels Desktop for the current user
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

user_count=$(/usr/local/bin/prlctl list -a | grep -oE '\{[a-f0-9\-]+\}' | wc -l | awk '{$1=$1};1')

if [[ $user_count ]]; then
  echo "$user_count"
else
  echo "No VMs found"
fi

exit 0
