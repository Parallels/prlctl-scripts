#!/bin/bash

############
# Restrict operations on the Parallels Desktop
#
# This script will restrict operations on the Parallels Desktop
# This will make the user input the password for the following operations:
# - Add a VM
# - Create a VM
# - Clone a VM
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

prlsrvctl set --require-pwd add-vm:on && prlcrvctl set --require-pwd create-vm:on && prlcrvctl set
--require-pwd clone-vm:on

if [[ $? -eq 0 ]]; then
  echo "Success"
else
  echo "Failed"
fi

exit 0
