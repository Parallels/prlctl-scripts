#!/bin/bash

############
# Get all machines from all users
#
# This script will get all virtual machines from all users in the system
# You will be able to filter the machines by status and format the output
#
# You can use the following options:
# -s | --status: Filter the machines by status
# -f | --format: Format the output
#
# Example:
# ./get-machines-all-users.sh -s running -f csv
############

STATUS=""
FORMAT=""

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
  -s | --status)
    STATUS="$2"
    shift # move past argument
    shift # move past value
    ;;
  -f | --format)
    FORMAT="$2"
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

lines=""

# Create an empty temporary file
temp_file=$(mktemp /tmp/uuids.XXXXXX)
temp_names=$(mktemp /tmp/names.XXXXXX)

for user in $(get_host_users); do
  line=""
  id=""
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
        machineName=$(echo "$input_data" | awk -v filter="$uuid" '$1 ~ filter { $1=$2=$3=""; gsub(/^ */, ""); print }')
        echo "$machineName" >>"$temp_names"
      fi
    fi
  done
done

if [ "$FORMAT" = "csv" ]; then
  lines=$(cat "$temp_names" | tr '\n' ',' | sed 's/,$//')
else
  lines=$(cat "$temp_names")
fi

rm "$temp_file"  # Cleanup the temporary file
rm "$temp_names" # Cleanup the temporary file

if [[ $lines ]]; then
  echo "$lines"
else
  echo "No Machines found"
fi

exit 0
