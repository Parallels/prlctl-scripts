#!/bin/bash

get_host_users() {
  dscl . list /Users | grep -v "^_" | grep '\S'
}

get_all_running_machines() {
  lines=""

  # Create an empty temporary file
  temp_file=$(mktemp /tmp/uuids.XXXXXX)
  temp_names=$(mktemp /tmp/names.XXXXXX)

  for user in $(get_host_users); do
    line=""
    id=""
    [ -n "${user}" ] && [ -e "/Users/${user}" ] || continue

    input_data=$(prlctl list -a)
    filtered_data=$(echo "$input_data" | awk -v filter="running" '$2 == filter {gsub(/[{}]/, "", $1); print $1}')

    echo "$filtered_data" | awk '{gsub(/[{}]/, "", $1); print $1}' | while read uuid; do
      if ! grep -q "$uuid" "$temp_file"; then
        if [ "$uuid" != "UUID" ]; then
          echo "$uuid" >>"$temp_file"
          machineName=$(echo "$input_data" | awk -v filter="$uuid" '$1 ~ filter {gsub(/[{}]/, "", $1); print $1}')
          printf "$machineName;" >>"$temp_names"
        fi
      fi
    done
  done

  lines=$(cat "$temp_names" | sed 's/;$//')
  rm "$temp_file"  # Cleanup the temporary file
  rm "$temp_names" # Cleanup the temporary file
  echo "$lines"
}

suspend() {
  os=$(prlctl list -i $1 | grep "OS:" | cut -f2 -d":" | tr -d '[:space:]')
  if [ "$os" != "macosx" ]; then
    echo "Suspending $1"
    prlctl suspend "$1"
    return
  fi
  echo "Ignoring $1, suspend not available"
}

echo "Press ctrl + c to exit"
PREVIOUS_STATE="No"
while true; do
  RESULT=$(ioreg -r -k AppleClamshellState | grep AppleClamshellState | cut -f2 -d"=" | tr -d '[:space:]')

  if [ "$RESULT" == "Yes" ]; then
    if [ "$PREVIOUS_STATE" == "No" ]; then
      echo "Going to sleep..."
      PREVIOUS_STATE="Yes"
      MACHINES=$(get_all_running_machines)
      IFS=';' read -ra MACHINES_ARRAY <<< "$MACHINES"
      for i in "${MACHINES_ARRAY[@]}"; do
        suspend "$i"
      done
      echo "Done"
    fi
  else
    if [ "$PREVIOUS_STATE" == "Yes" ]; then
      echo "Waking up..."
      PREVIOUS_STATE="No"
      echo "Done"
    fi
  fi
  sleep 1
done