#!/bin/bash

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

lines=$(cat "$temp_names" | tr '\n' ',' | sed 's/,$//')
rm "$temp_file"  # Cleanup the temporary file
rm "$temp_names" # Cleanup the temporary file

if [[ $lines ]]; then
  echo "$lines"
else
  echo "No Machines found"
fi

exit 0
