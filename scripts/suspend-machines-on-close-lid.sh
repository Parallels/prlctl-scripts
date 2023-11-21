#!/bin/bash
OPS="RUN"
while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
  -i | --install)
    OPS="INSTALL"
    shift # move past argument
    shift # move past value
    ;;
  -u | --uninstall)
    OPS="UNINSTALL"
    shift # move past argument
    shift # move past value
    ;;
  *)
    OPS="RUN"
    shift # move past argument
    ;;
  esac
done

get_host_users() {
  dscl . list /Users | grep -v "^_" | grep '\S'
}

get_all_running_machines() {
  lines=""

  # Create an empty temporary file
  temp_file=$(mktemp /tmp/uuids.XXXXXX)
  temp_names=$(mktemp /tmp/names.XXXXXX)
  echo "Getting Users"

  for user in $(get_host_users); do
    line=""
    id=""
    [ -n "${user}" ] && [ -e "/Users/${user}" ] || continue

    input_data=$(sudo -u $user /usr/local/bin/prlctl list -a)
    if [ -z "$input_data" ]; then
      echo "No data"
      continue
    fi

    filtered_data=$(echo "$input_data" | awk -v filter="running" '$2 == filter {gsub(/[{}]/, "", $1); print $1}')

    echo "$filtered_data" | awk '{gsub(/[{}]/, "", $1); print $1}' | while read uuid; do
      if ! grep -q "$uuid" "$temp_file"; then
        if [ "$uuid" != "UUID" ]; then
          echo "$uuid" >>"$temp_file"
          machineName=$(echo "$input_data" | awk -v filter="$uuid" '$1 ~ filter {gsub(/[{}]/, "", $1); print $1}')
          printf "$machineName;" >>"$temp_names"
          suspend "$user" "$uuid"
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
  echo "User: $1 and Machine: $2"
  if [ -z "$1" ]; then
    echo "No user name provided"
    return
  fi
  if [ -z "$2" ]; then
    echo "No machine name provided"
    return
  fi

  os=$(sudo -u $1 /usr/local/bin/prlctl list -i $2 | grep "OS:" | cut -f2 -d":" | tr -d '[:space:]')
  if [ "$os" != "macosx" ]; then
    echo "Suspending $2"
    sudo -u $1 /usr/local/bin/prlctl suspend "$2"
    return
  fi
  echo "Ignoring $1, suspend not available"
}

uninstall() {
 echo "Uninstalling Service on $1"

  launchctl unload /Library/LaunchDaemons/com.parallels.suspend-machines-on-close-lid.plist
  rm /Library/LaunchDaemons/com.parallels.suspend-machines-on-close-lid.plist
  echo "Done"
}

install() {
 echo "Installing Service on $1"
 echo "<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>UserName</key>
  <string>root</string>
  <key>Label</key>
  <string>com.parallels.suspend-machines-on-close-lid</string>
  <key>Program</key>
  <string>$1/suspend-machines-on-close-lid.sh</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardErrorPath</key>
  <string>/tmp/suspend-machines-on-close-lid.job.err</string>
  <key>StandardOutPath</key>
  <string>/tmp/suspend-machines-on-close-lid.job.out</string> 
</dict>
</plist>" > /Library/LaunchDaemons/com.parallels.suspend-machines-on-close-lid.plist
  
  chown root:wheel /Library/LaunchDaemons/com.parallels.suspend-machines-on-close-lid.plist
  chmod 644 /Library/LaunchDaemons/com.parallels.suspend-machines-on-close-lid.plist

  launchctl unload /Library/LaunchDaemons/com.parallels.suspend-machines-on-close-lid.plist
  launchctl load /Library/LaunchDaemons/com.parallels.suspend-machines-on-close-lid.plist
  launchctl start /Library/LaunchDaemons/com.parallels.suspend-machines-on-close-lid
  echo "Done"
}

run() {
  username=$(id -un)
  echo "Running Service as $username"
  echo "Press ctrl + c to exit"
  PREVIOUS_STATE="No"
  while true; do
    RESULT=$(ioreg -r -k AppleClamshellState | grep AppleClamshellState | cut -f2 -d"=" | tr -d '[:space:]')

    if [ "$RESULT" == "Yes" ]; then
      if [ "$PREVIOUS_STATE" == "No" ]; then
        echo "Going to sleep..."
        PREVIOUS_STATE="Yes"
        get_all_running_machines
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
}

if [ "$OPS" == "INSTALL" ]; then
  install "/Users/cjlapao/code/parallels/prlctl-scripts/scripts"
elif [ "$OPS" == "UNINSTALL" ]; then
  uninstall
else
  run
fi