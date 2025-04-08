#!/bin/bash

############
# Get all machines from the Parallels Server
#
# This script will get all virtual machines from the Parallels Desktop
# You will be able to filter the machines by status and format the output
#
# You can use the following options:
# -s | --status: Filter the machines by status
# -f | --format: Format the output
#
# Example:
# ./get-machines.sh -s running -f csv
#
# This will get all running machines and format the output as a csv
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

if [ "$FORMAT" = "csv" ]; then
  /usr/local/bin/prlctl list -a | awk -v my_status="$STATUS" '$2 ~ my_status { $1=$2=$3=""; gsub(/^ */, ""); print }' | tr '\n' ',' | sed 's/,$//'
else
  /usr/local/bin/prlctl list -a | awk -v my_status="$STATUS" '$2 ~ my_status { $1=$2=$3=""; gsub(/^ */, ""); print }'
fi

if [[ $lines ]]; then
  echo "$lines"
else
  echo "No Machines found"
fi

exit 0
