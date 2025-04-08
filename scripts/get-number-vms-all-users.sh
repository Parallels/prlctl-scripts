#!/bin/bash

############
# Get the number of virtual machines from all users
#
# This script will get the number of virtual machines from all users from the Parallels Desktop
# You will be able to filter the machines by status
#
# You can use the following options:
# -s | --status: Filter the machines by status
#
# Example:
# ./get-number-vms-all-users.sh -s running
############

STATUS=""

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
  -s | --status)
    STATUS="$2"
    shift # move past argument
    shift # move past value
    ;;
  *)
    # unknown option
    shift # move past argument
    ;;
  esac
done

get_host_users() {
  dscl . list /Users | grep -v "^_" | grep '\S'
}

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

# Create an empty temporary file
temp_file=$(mktemp /tmp/uuids.XXXXXX)
for user in $(get_host_users); do
  [ -n "${user}" ] && [ -e "/Users/${user}" ] || continue

  input_data=$(sudo -u $user /usr/local/bin/prlctl list -a)
  filtered_data=$input_data

  if [ -n "$STATUS" ]; then
    filtered_data=$(echo "$input_data" | awk -v filter="$STATUS" '$2 == filter {gsub(/[{}]/, "", $1); print $1}')
  fi

  echo "$filtered_data" | awk '{gsub(/[{}]/, "", $1); print $1}' | while read uuid; do
    if ! grep -q "$uuid" "$temp_file"; then
      if [ "$uuid" != "UUID" ]; then
        echo "$uuid" >>"$temp_file"
      fi
    fi
  done
done

user_count=$(wc -l "$temp_file" | awk '{$1=$1};1' | cut -d' ' -f1)

rm "$temp_file" # Cleanup the temporary file

if [[ $user_count ]]; then
  echo "$user_count"
else
  echo "No VMs found"
fi

exit 0
