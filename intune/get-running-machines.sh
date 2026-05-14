#!/bin/bash

STATUS="running"
FORMAT=""

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

  if [ -n "$filtered_data" ]; then
    echo "$filtered_data" | awk '{gsub(/[{}]/, "", $1); print $1}' | while read uuid; do
      if ! grep -q "$uuid" "$temp_file"; then
        if [ "$uuid" != "UUID" ]; then
          echo "$uuid" >>"$temp_file"
          machineName=$(echo "$input_data" | awk -v filter="$uuid" '$1 ~ filter { $1=$2=$3=""; gsub(/^ */, ""); print }')
          if [ "$machineName" != "" ] && [ "$machineName" != NAME* ]; then
            echo "$machineName" >>"$temp_names"
          fi
        fi
      fi
    done
  fi
done

lines=$(cat "$temp_names" | tr '\n' ',' | sed 's/,$//')
rm "$temp_file"  # Cleanup the temporary file
rm "$temp_names" # Cleanup the temporary file

echo "$lines"
