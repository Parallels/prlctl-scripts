#!/bin/bash

############
# Check for Windows Updates
#
# This script will check for Windows Updates or Parallels Desktop Guest Tools updates
# and install them either unattended or with user prompts.
#
# Requirements:
# - prlctl
# - jq
# - osascript
#
# Parameters:
# $4: Mode (check, list-updates, install, uninstall, check-and-install)
# $5: Unattended (optional) = true or false
# $6: Auto Reboot (optional) = true or false
# $7: Verbose (optional) | default is true if not provided
#     It will print more information during the execution
# $8: Force (optional) | defaults is false if not provided
#     Forces the script to run in every windows
#     vm regardless of the state, if the machine is not running it
#     will be started and then| default is false if not provided

MODE="$4"
AUTO_REBOOT="false"
USER_PROMPT="true"
VERBOSE="true"
OUTPUT_FILE=""
TARGET_VM_ID=""
FORCE="false"
USER=""
USER_ID=""
TARGET_VM_IDS=()
DEBUG="true"
KB=""

# check if the unattended parameter is true
if [ "$5" = "true" ]; then
  USER_PROMPT="false"
fi

# check if the auto reboot parameter is true
if [ "$6" = "true" ]; then
  AUTO_REBOOT="true"
fi

if [ "$7" = "true" ]; then
  VERBOSE="true"
fi

if [ "$8" = "true" ]; then
  FORCE="true"
fi

if [ -z "$MODE" ]; then
  MODE="check-and-install"
fi

function check_for_requirements() {
  prlctl_installed=$(which prlctl)
  if [[ -z "$prlctl_installed" ]]; then
    echo "prlctl is not installed"
    exit 1
  fi

  # testing if jq is correctly working
  if [[ -f "/tmp/jq" ]]; then
    version=$(/tmp/jq --version)
    if [[ $? -ne 0 ]]; then
      rm -f /tmp/jq
      echo "jq is not working, version: $version"
    fi
  fi

  # Check if jq is installed
  if [[ ! -f "/tmp/jq" ]]; then
    if [ "$VERBOSE" = "true" ]; then
      echo "jq is not installed. Installing temporary version..."
    fi

    arch=$(uname -m)
    if [ "$arch" = "x86_64" ]; then
      arch="amd64"
    fi

    curl -Ls -o /tmp/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-"$arch"
    chmod +x /tmp/jq
    xattr -dr com.apple.quarantine /tmp/jq
  fi
}

function list_all_users() {
  dscl . list /Users | while read user; do
    home=$(dscl . -read /Users/"$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    if [[ -d "$home" && "$home" == /Users/* && "$user" != _* ]]; then
      echo "$user"
    fi
  done
}

function list_vms() {
  STATUS="and .State == \"running\""
  if [ "$FORCE" = "true" ]; then
    STATUS=""
  fi
  VMS=$(sudo -u $USER prlctl list -a -i --json | /tmp/jq -r "map(select((.OS == \"win-10\" or .OS == \"win-11\") $STATUS) | {id:.ID, name: .Name, tools_state: .GuestTools.state, state: .State})")
  echo "$VMS"
}

function resume_vm() {
  VM_ID=$1
  CURRENT_STATE=$2

  # If the current state is not provided, get it from prlctl
  if [ -z "$CURRENT_STATE" ]; then
    CURRENT_STATE=$(sudo -u "$USER" prlctl list "$VM_ID" -a -i --json | /tmp/jq -r ".[0] | .State")
  fi

  if [ "$CURRENT_STATE" = "paused" ]; then
    sudo -u "$USER" prlctl resume "$VM_ID"
  fi
  if [ "$CURRENT_STATE" = "suspended" ]; then
    sudo -u "$USER" prlctl resume "$VM_ID"
  fi
  if [ "$CURRENT_STATE" = "stopped" ]; then
    sudo -u "$USER" prlctl start "$VM_ID"
  fi
}

function pause_vm() {
  VM_ID=$1
  sudo -u "$USER" prlctl pause "$VM_ID"
}

function stop_vm() {
  VM_ID=$1
  sudo -u "$USER" prlctl stop "$VM_ID"
}

function suspend_vm() {
  VM_ID=$1
  sudo -u "$USER" prlctl suspend "$VM_ID"
}

function await_for_vm_to_be_running() {
  VM_ID=$1
  MAX_WAIT_TIME=10
  while true; do
    CURRENT_STATE=$(sudo -u "$USER" prlctl list "$VM_ID" -a -i --json | /tmp/jq -r ".[0] | .State")
    if [ "$CURRENT_STATE" = "running" ]; then
      break
    fi
    sleep 1
    MAX_WAIT_TIME=$((MAX_WAIT_TIME - 1))
    if [ $MAX_WAIT_TIME -eq 0 ]; then
      echo "Error: VM $VM_ID did not start in time"
      exit 1
    fi
  done
  while true; do
    sudo -u $USER prlctl exec $VM_ID cmd /c 'echo "hello" > $null'
    last_exit_code=$?
    if [ $last_exit_code -eq 0 ]; then
      break
    fi
    sleep 1
    MAX_WAIT_TIME=$((MAX_WAIT_TIME - 1))
    if [ $MAX_WAIT_TIME -eq 0 ]; then
      echo "Error: VM $VM_ID did not start in time"
      exit 1
    fi
  done
}

function initialize_vm() {
  VM_ID=$1
  VM_STATE=$2
  if [ -z "$VM_STATE" ]; then
    echo "VM state is not provided, getting it from prlctl"
    VM_STATE=$(sudo -u "$USER" prlctl list "$VM_ID" -a -i --json | /tmp/jq -r ".[0] | .State")
  fi

  if [ "$VM_STATE" = "running" ]; then
    await_for_vm_to_be_running "$VM_ID"
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ]; then
      echo "Error: Failed to resume VM $VM_ID"
      exit 1
    fi
  fi
  if [ "$VM_STATE" = "paused" ]; then
    resume_vm "$VM_ID" "$VM_STATE"
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ]; then
      echo "Error: Failed to resume VM $VM_ID"
      exit 1
    fi
    await_for_vm_to_be_running "$VM_ID"
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ]; then
      echo "Error: Failed to resume VM $VM_ID"
      exit 1
    fi
  fi
  if [ "$VM_STATE" = "suspended" ]; then
    resume_vm "$VM_ID" "$VM_STATE"
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ]; then
      echo "Error: Failed to resume VM $VM_ID"
      exit 1
    fi
    await_for_vm_to_be_running "$VM_ID"
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ]; then
      echo "Error: Failed to resume VM $VM_ID"
      exit 1
    fi
  fi
  if [ "$VM_STATE" = "stopped" ]; then
    resume_vm "$VM_ID" "$VM_STATE"
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ]; then
      echo "Error: Failed to resume VM $VM_ID"
      exit 1
    fi
    await_for_vm_to_be_running "$VM_ID"
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ]; then
      echo "Error: Failed to resume VM $VM_ID"
      exit 1
    fi
  fi
}

function set_vm_to_previous_state() {
  VM_ID=$1
  VM_STATE=$2
  if [ -z "$VM_STATE" ]; then
    echo "Error: VM state is not provided"
    exit 1
  fi

  if [ "$VM_STATE" = "stopped" ]; then
    stop_vm "$VM_ID"
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ]; then
      echo "Error: Failed to stop VM $VM_ID"
      exit 1
    fi
  fi
  if [ "$VM_STATE" = "paused" ]; then
    pause_vm "$VM_ID"
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ]; then
      echo "Error: Failed to pause VM $VM_ID"
      exit 1
    fi
  fi
  if [ "$VM_STATE" = "suspended" ]; then
    suspend_vm "$VM_ID"
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ]; then
      echo "Error: Failed to suspend VM $VM_ID"
      exit 1
    fi
  fi
}
function install_modules() {
  VM_ID=$1
  OUTPUT=$(sudo -u $USER prlctl exec $VM_ID powershell -Command "Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force; usoClient StartScan; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force; Install-Module PSWindowsUpdate -Force -AllowClobber;")
}

function get_list_of_updates() {
  VM_ID=$1
  VM_STATE=$2

  initialize_vm "$VM_ID" "$VM_STATE"
  last_exit_code=$?
  if [ $last_exit_code -ne 0 ]; then
    echo "Error: Failed to resume VM $VM_ID"
    exit 1
  fi

  # Create a temporary file to store the complete output
  temp_output_file=$(mktemp)

  # Execute the command and redirect all output to the temporary file
  sudo -u $USER prlctl exec $VM_ID powershell -Command "Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force; usoClient StartScan; Import-Module PSWindowsUpdate; Get-WindowsUpdate | ForEach-Object { \$_ | Select-Object -Property Title,KB,KBArticleIDs,Size,LastDeploymentChangeTime,Status,RebootRequired,IsInstalled } | ConvertTo-Json -Depth 5" >"$temp_output_file" 2>/dev/null

  last_exit_code=$?
  if [ $last_exit_code -ne 0 ] && [ $last_exit_code -ne 2 ]; then
    echo "Error: Failed to get updates for $VM_ID"
    exit 1
  fi

  # Read and clean the file content
  raw_updates=$(cat "$temp_output_file")

  # If the output is empty, set it to an empty array
  if [ -z "$raw_updates" ]; then
    raw_updates="[]"
  fi

  # Clean up the raw updates output
  raw_updates=$(echo "$raw_updates" | grep -v "WARNING" | grep -v "^$")

  # If the output starts with { (single object) and doesn't end with ], wrap it in array brackets
  if [[ "$raw_updates" =~ ^\{.*$ ]] && [[ ! "$raw_updates" =~ \]$ ]]; then
    raw_updates="[$raw_updates]"
  fi

  # Process the updates with jq and ensure it's an array
  updates=$(echo "$raw_updates" | /tmp/jq -c -r 'map({title: .Title, kb: .KB, kbArticleIDs: .KBArticleIDs, size: .Size, lastDeploymentChangeTime: .LastDeploymentChangeTime, status: .Status, requires_reboot: .RebootRequired, is_installed: .IsInstalled})')
  rm -f "$temp_output_file"

  set_vm_to_previous_state "$VM_ID" "$VM_STATE"
  last_exit_code=$?
  if [ $last_exit_code -ne 0 ]; then
    echo "Error: Failed to set VM $VM_ID to previous state"
    exit 1
  fi

  echo "$updates"
}

function install_windows_updates() {
  VM_ID=$1
  TARGET_KB=$2
  VM_STATE=$3

  initialize_vm "$VM_ID" "$VM_STATE"
  last_exit_code=$?
  if [ $last_exit_code -ne 0 ]; then
    echo "Error: Failed to resume VM $VM_ID"
    exit 1
  fi

  if [ -z "$TARGET_KB" ]; then
    if [ "$AUTO_REBOOT" = "true" ]; then
      RESULT=$(sudo -u $USER prlctl exec $VM_ID powershell -Command "Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force *>\$null; Install-Module PSWindowsUpdate -Force -AllowClobber; Import-Module PSWindowsUpdate; Install-WindowsUpdate -AcceptAll -AutoReboot | ConvertTo-Json -Depth 5")
    else
      RESULT=$(sudo -u $USER prlctl exec $VM_ID powershell -Command "Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force *>\$null; Install-Module PSWindowsUpdate -Force -AllowClobber; Import-Module PSWindowsUpdate; Install-WindowsUpdate -AcceptAll | ConvertTo-Json -Depth 5")
    fi
  else
    if [ "$AUTO_REBOOT" = "true" ]; then
      RESULT=$(sudo -u $USER prlctl exec $VM_ID powershell -Command "Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force *>\$null; Install-Module PSWindowsUpdate -Force -AllowClobber; Import-Module PSWindowsUpdate; Install-WindowsUpdate -KBArticleID $TARGET_KB -AcceptAll -AutoReboot | ConvertTo-Json -Depth 5")
    else
      RESULT=$(sudo -u $USER prlctl exec $VM_ID powershell -Command "Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force *>\$null; Install-Module PSWindowsUpdate -Force -AllowClobber; Import-Module PSWindowsUpdate; Install-WindowsUpdate -KBArticleID $TARGET_KB -AcceptAll | ConvertTo-Json -Depth 5")
    fi
  fi

  set_vm_to_previous_state "$VM_ID" "$VM_STATE"
  last_exit_code=$?
  if [ $last_exit_code -ne 0 ]; then
    echo "Error: Failed to set VM $VM_ID to previous state"
    exit 1
  fi
  echo "Windows Update installed"
}

function uninstall_windows_updates() {
  VM_ID=$1
  TARGET_KB=$2
  VM_STATE=$3

  initialize_vm "$VM_ID" "$VM_STATE"
  last_exit_code=$?
  if [ $last_exit_code -ne 0 ]; then
    echo "Error: Failed to resume VM $VM_ID"
    exit 1
  fi

  RESULT=$(sudo -u $USER prlctl exec $VM_ID powershell -Command "Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force; Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force *>\$null; Install-Module PSWindowsUpdate -Force -AllowClobber; Import-Module PSWindowsUpdate; Uninstall-WindowsUpdate -KBArticleID $TARGET_KB | ConvertTo-Json -Depth 5")

  set_vm_to_previous_state "$VM_ID" "$VM_STATE"
  last_exit_code=$?
  if [ $last_exit_code -ne 0 ]; then
    echo "Error: Failed to set VM $VM_ID to previous state"
    exit 1
  fi
  echo "$RESULT"
}

function update_pd_tools() {
  VM_ID=$1
  RESULT=$(sudo -u $USER prlctl installtools $VM_ID)
  if [ $? -ne 0 ]; then
    echo "Error: Failed to update PD tools for $VM_ID"
    exit 1
  fi

  echo "$RESULT"
}

# Function to add updates to the JSON structure
function add_vm_updates() {
  local vm_id=$1
  local vm_name=$2
  local updates=$3
  local tools_state=$4

  has_updates=$(echo "$updates" | /tmp/jq 'length > 0')
  # Create a JSON object for this VM with its updates
  vm_updates=$(/tmp/jq -n \
    --arg name "$vm_name" \
    --arg id "$vm_id" \
    --arg tools_state "$tools_state" \
    --arg has_updates "$has_updates" \
    --argjson updates "$updates" \
    '{name: $name, id: $id, guest_tools: $tools_state, updates: $updates, has_updates: $has_updates}')

  # Add to our array of all updates
  ALL_UPDATES+=("$vm_updates")
}

# Function to save all updates to a JSON file
function save_updates_to_json() {
  local output_file=${OUTPUT_FILE:-"windows_updates.json"}

  # Combine all VM update objects into a single JSON array and save to file
  if ! printf '%s\n' "${ALL_UPDATES[@]}" | /tmp/jq -s '.' >"$output_file" 2>/dev/null; then
    if [ "$VERBOSE" = "true" ]; then
      echo "Warning: Some non-critical errors occurred while writing to $output_file"
    fi
  fi
}

function get_vms_ids() {
  VMS=$(list_vms)
  while IFS= read -r line; do
    VM_ARRAY+=("$line")
  done < <(echo "$VMS" | /tmp/jq -c '.[]')

  for VM in "${VM_ARRAY[@]}"; do
    VM_IDS+=($(echo "$VM" | /tmp/jq -r '.id'))
  done

  echo "${VM_IDS[@]}"
}

function print_array() {
  local array=("$@")
  for item in "${array[@]}"; do
    printf '%s\n' "$item"
  done
}

function check_for_updates() {
  VMS=$(list_vms)

  if [ ${#VM_ARRAY[@]} -eq 0 ]; then
    VM_ARRAY=()
    while IFS= read -r line; do
      VM_ARRAY+=("$line")
    done < <(echo "$VMS" | /tmp/jq -c '.[]')
  fi

  if [ "$VERBOSE" = "true" ]; then
    echo "Found ${#VM_ARRAY[@]} VM(s) running windows, checking for updates"
  fi

  if [ ${#VM_ARRAY[@]} -eq 0 ]; then
    echo "No running Windows VMs found"
    exit 0
  fi

  # Initialize an empty JSON array to store all VM update information
  ALL_UPDATES=()

  for VM in "${VM_ARRAY[@]}"; do
    vm_id=$(echo "$VM" | /tmp/jq -r '.id')
    vm_name=$(echo "$VM" | /tmp/jq -r '.name')
    vm_state=$(echo "$VM" | /tmp/jq -r '.state')
    tools_state=$(echo "$VM" | /tmp/jq -r '.tools_state')
    if [ "$TARGET_VM_ID" != "" ] && [ "$TARGET_VM_ID" != "$vm_id" ]; then
      echo "Skipping $vm_name ($vm_id) because it's not the target VM"
      continue
    fi

    # Skip if we have a list of target VM IDs and this VM is not in the list
    if [ ${#TARGET_VM_IDS[@]} -gt 0 ]; then
      is_in_array=false
      for target_id in "${TARGET_VM_IDS[@]}"; do
        if [ "$target_id" = "$vm_id" ]; then
          is_in_array=true
          break
        fi
      done

      if [ "$is_in_array" = "false" ]; then
        if [ "$VERBOSE" = "true" ]; then
          echo "Skipping $vm_name ($vm_id) because it's not in the target VM list"
        fi
        continue
      fi
    fi
    if [ "$VERBOSE" = "true" ]; then
      echo "Checking for updates in $vm_name ($vm_id)"
    fi
    install_modules "$vm_id"

    updates=$(get_list_of_updates "$vm_id" "$vm_state" | tail -n1)
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ] && [ $last_exit_code -ne 2 ]; then
      echo "Error: Failed to get updates for $vm_name ($vm_id)"
      exit 1
    fi
    # Check if updates is an empty array
    HAS_UPDATES=$(echo "$updates" | /tmp/jq 'length > 0')
    HAS_TOOLS_UPDATE="false"
    if [ "$tools_state" = "outdated" ]; then
      HAS_UPDATES="true"
      HAS_TOOLS_UPDATE="true"
    fi
    if [ "$HAS_UPDATES" = "false" ] && [ "$tools_state" = "outdated" ]; then
      HAS_UPDATES="true"
      HAS_TOOLS_UPDATE="true"
    fi

    # Build a JSON object with name, id, and a boolean indicating if updates are available
    vm_update_status=$(/tmp/jq -n \
      --arg name "$vm_name" \
      --arg id "$vm_id" \
      --argjson has_updates "$HAS_UPDATES" \
      --argjson has_tools_update "$HAS_TOOLS_UPDATE" \
      '{name: $name, id: $id, has_updates: $has_updates, has_tools_update: $has_tools_update}')

    if [ "$VERBOSE" = "true" ]; then
      if [ "$HAS_UPDATES" = "true" ]; then
        echo "$vm_name has updates available"
      else
        echo "$vm_name has no updates available"
      fi
    fi
    ALL_UPDATES+=("$vm_update_status")
  done

  if [ "$OUTPUT_TO_FILE" = "true" ]; then
    save_updates_to_json
  else
    OUTPUT_FILE=$(mktemp)
    save_updates_to_json
    if [ -f "$OUTPUT_FILE" ]; then
      while IFS= read -r line; do
        echo "$line"
      done <"$OUTPUT_FILE"
      rm -f "$OUTPUT_FILE"
    fi
  fi
}

function list_updates() {
  VMS=$(list_vms)

  if [ ${#VM_ARRAY[@]} -eq 0 ]; then
    VM_ARRAY=()
    while IFS= read -r line; do
      VM_ARRAY+=("$line")
    done < <(echo "$VMS" | /tmp/jq -c '.[]')
  fi

  if [ "$VERBOSE" = "true" ]; then
    echo "Found ${#VM_ARRAY[@]} VM(s) running windows, checking for updates"
  fi

  if [ ${#VM_ARRAY[@]} -eq 0 ]; then
    echo "No running Windows VMs found"
    exit 0
  fi

  # Initialize an empty JSON array to store all VM update information
  ALL_UPDATES=()

  for VM in "${VM_ARRAY[@]}"; do
    vm_id=$(echo "$VM" | /tmp/jq -r '.id')
    vm_name=$(echo "$VM" | /tmp/jq -r '.name')
    tools_state=$(echo "$VM" | /tmp/jq -r '.tools_state')
    vm_state=$(echo "$VM" | /tmp/jq -r '.state')
    if [ "$TARGET_VM_ID" != "" ] && [ "$TARGET_VM_ID" != "$vm_id" ]; then
      echo "Skipping $vm_name ($vm_id) because it's not the target VM"
      continue
    fi

    # Skip if we have a list of target VM IDs and this VM is not in the list
    if [ ${#TARGET_VM_IDS[@]} -gt 0 ]; then
      is_in_array=false
      for target_id in "${TARGET_VM_IDS[@]}"; do
        if [ "$target_id" = "$vm_id" ]; then
          is_in_array=true
          break
        fi
      done

      if [ "$is_in_array" = "false" ]; then
        if [ "$VERBOSE" = "true" ]; then
          echo "Skipping $vm_name ($vm_id) because it's not in the target VM list"
        fi
        continue
      fi
    fi
    if [ "$VERBOSE" = "true" ]; then
      echo "Checking for updates in $vm_name ($vm_id)"
    fi
    install_modules "$vm_id"
    updates=$(get_list_of_updates "$vm_id" "$vm_state" | tail -n1)
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ] && [ $last_exit_code -ne 2 ]; then
      echo "Error: Failed to get updates for $vm_name ($vm_id)"
      exit 1
    fi

    # Check if updates is an empty array
    HAS_UPDATES=$(echo "$updates" | /tmp/jq 'length > 0')
    if [ "$HAS_UPDATES" = "false" ]; then
      if [ "$tools_state" = "outdated" ]; then
        HAS_UPDATES="true"
      fi
    fi

    add_vm_updates "$vm_id" "$vm_name" "$updates" "$tools_state"
  done

  if [ "$OUTPUT_TO_FILE" = "true" ]; then
    save_updates_to_json
  else
    OUTPUT_FILE=$(mktemp)
    save_updates_to_json
    if [ -f "$OUTPUT_FILE" ]; then
      while IFS= read -r line; do
        echo "$line"
      done <"$OUTPUT_FILE"
      rm -f "$OUTPUT_FILE"
    fi
  fi
}

function check_and_install_updates() {
  local verbose=false
  # Check if any VM has updates available
  if [ "$VERBOSE" = "true" ]; then
    echo "Checking for updates"
    verbose=true
    VERBOSE=false
  fi
  result=$(list_updates)
  has_updates=$(echo "$result" | /tmp/jq 'map(.updates) | any')
  if [ "$verbose" = "true" ]; then
    VERBOSE=true
  fi

  # setting the auto reboot to true if the script is run unattended
  if [ "$USER_PROMPT" = "false" ]; then
    AUTO_REBOOT="true"
  fi

  if [ "$has_updates" = "true" ]; then
    # Parse the result JSON to get details about which VMs have updates

    # Iterate through each VM in the result array
    vm_count=$(echo "$result" | /tmp/jq 'length')
    for ((i = 0; i < $vm_count; i++)); do
      vm_name=$(echo "$result" | /tmp/jq -r ".[$i].name")
      vm_id=$(echo "$result" | /tmp/jq -r ".[$i].id")
      has_tools_update=$(echo "$result" | /tmp/jq -r ".[$i].guest_tools" | grep -q "outdated" && echo "true" || echo "false")
      has_vm_updates=$(echo "$result" | /tmp/jq -r ".[$i].updates | length > 0")

      updates=$(echo "$result" | /tmp/jq -r ".[$i].updates" | tr -d '\n' | sed 's/},/},/g')
      # Write updates to a temporary file to avoid shell interpretation issues
      temp_updates_file=$(mktemp)
      temp_reboot_file=$(mktemp)
      printf '%s' "$updates" >"$temp_updates_file"

      /tmp/jq -c '.[]' "$temp_updates_file" | while IFS= read -r update; do
        status=$(printf '%s' "$update" | /tmp/jq -r '.status')
        requires_reboot=$(printf '%s' "$update" | /tmp/jq -r '.requires_reboot')

        if [ "$status" = "-D-----" ] && [ "$requires_reboot" = "true" ]; then
          echo "true" >"$temp_reboot_file"
        fi
      done
      # Read the result back from the temporary file
      if [ -f "$temp_reboot_file" ] && [ "$(cat "$temp_reboot_file")" = "true" ]; then
        REQUIRES_REBOOT="true"
      fi

      if [ "$has_vm_updates" = "true" ] || [ "$has_tools_update" = "true" ]; then
        if [ "$VERBOSE" = "true" ]; then
          echo "Updates available for the following VMs:"
        fi
        list_updates=""
        if [ "$has_tools_update" = "true" ]; then
          list_updates="Parallels Desktop Guest Tools"
        fi

        if [ "$VERBOSE" = "true" ]; then
          update_count=$(echo "$result" | /tmp/jq -r ".[$i].updates | length")
          echo "  - $vm_name (ID: $vm_id) has $update_count updates available"

          # List the updates if verbose mode is enabled
          updates=$(echo "$result" | /tmp/jq -r ".[$i].updates")
          echo "$updates" | /tmp/jq -r '.[] | "    * " + .title + " (KB: " + .kb + ")"' 2>/dev/null
          if [ "$has_tools_update" = "true" ]; then
            echo "    * Parallels Desktop Guest Tools"
          fi
        fi

        list_updates="$list_updates\n$(echo "$updates" | /tmp/jq -r '.[].updates | .title' 2>/dev/null)"

        TARGET_VM_IDS+=("$vm_id")
        CAN_INSTALL="false"
        UPDATES_TYPE=""
        if [ "$has_vm_updates" = "true" ]; then
          UPDATES_TYPE="  - Windows Security Updates"
        fi
        if [ "$has_tools_update" = "true" ]; then
          if [ -z "$UPDATES_TYPE" ]; then
            UPDATES_TYPE="  - Parallels Desktop Guest Tools"
          else
            UPDATES_TYPE="$UPDATES_TYPE\n  - Parallels Desktop Guest Tools"
          fi
        fi

        # Add this VM to the list of VMs that need updates
        if [ "$USER_PROMPT" = "true" ]; then
          response=$(
            launchctl asuser "$USER_ID" sudo -u "$USER" osascript <<EOF
try
  display dialog "There are updates available for VM $vm_name.\n$UPDATES_TYPE\n\nDo you want to install them?\\nWindows Updates Found:\n$(echo "$updates" | /tmp/jq -r '.[] | "- " + .title + " (KB: " + .kb + ")"')\n\n⚠️ ATTENTION: the VM might restart during the installation." with title "$vm_name Security Updates" buttons {"Install", "Cancel"} default button "Install"
  return "::Install"
on error errMsg number errNumber
  return "::Cancel"
end try
EOF
          )
          if [ "$response" = "::Cancel" ]; then
            CAN_INSTALL="false"
            if [ "$VERBOSE" = "true" ]; then
              echo "User cancelled the installation"
            fi
            exit 0
          fi
          if [ "$response" = "::Install" ]; then
            CAN_INSTALL="true"
            if [ "$VERBOSE" = "true" ]; then
              echo "User approved the installation"
            fi
          fi
        else
          CAN_INSTALL="true"
        fi

        if [ "$CAN_INSTALL" = "true" ]; then
          if [ "$has_vm_updates" = "true" ]; then
            install_windows_updates "$vm_id" "$KB"
            if [ "$REQUIRES_REBOOT" = "true" ]; then
              prlctl exec "$vm_id" powershell -Command "shutdown /r /t 0 /f"
            fi
          fi

          max_retries=18
          retries=0
          if [ "$has_tools_update" = "true" ]; then
            update_pd_tools "$vm_id"
            while [ "$has_tools_update" = "true" ]; do
              retries=$((retries + 1))
              if [ "$retries" -ge "$max_retries" ]; then
                echo "Tools update failed after $max_retries retries"
                break
              fi
              sleep 10
              echo "Checking if tools update is finished, retry $retries"
              has_tools_update=$(prlctl list "$vm_id" -a -i --json | /tmp/jq -r ".[0] | .GuestTools.state" | grep -q "installed" && echo "false" || echo "true")
            done
            if [ "$has_tools_update" = "true" ]; then
              echo "Tools update failed after $max_retries retries"
              exit 1
            else
              echo "Tools update finished"
            fi
          fi
        fi
      else
        echo "No updates available for $vm_name ($vm_id)"
      fi
    done
  fi
}

function install_updates() {
  if [ ${#TARGET_VM_IDS[@]} -eq 0 ]; then
    if [ -z "$TARGET_VM_ID" ]; then
      VMS=$(get_vms_ids)
      for VM_ID in "${VMS[@]}"; do
        echo "Adding $VM_ID to TARGET_VM_IDS"
        TARGET_VM_IDS+=("$VM_ID")
      done
    else
      TARGET_VM_IDS=("$TARGET_VM_ID")
    fi
  fi
  if [ "$VERBOSE" = "true" ]; then
    if [ -z "$KB" ]; then
      echo "Installing updates for ${#TARGET_VM_IDS[@]} VM(s) running windows"
    else
      echo "Installing KB $KB update for ${#TARGET_VM_IDS[@]} VM(s) running windows"
    fi
  fi
  echo "TARGET_VM_IDS: ${TARGET_VM_IDS[*]}"
  for TARGET_VM_ID in "${TARGET_VM_IDS[@]}"; do
    if [ "$VERBOSE" = "true" ]; then
      if [ -z "$KB" ]; then
        echo "Installing updates for $TARGET_VM_ID"
      else
        echo "Installing KB $KB update for $TARGET_VM_ID"
      fi
    fi
    install_windows_updates "$TARGET_VM_ID" "$KB"
  done
}

function uninstall_updates() {
  if [ ${#TARGET_VM_IDS[@]} -eq 0 ]; then
    if [ -z "$TARGET_VM_ID" ]; then
      VMS=$(get_vms_ids)
      for VM_ID in "${VMS[@]}"; do
        TARGET_VM_IDS+=("$VM_ID")
      done
    else
      TARGET_VM_IDS=("$TARGET_VM_ID")
    fi
  fi
  if [ -z "$KB" ]; then
    echo "No KB provided to uninstall"
    exit 1
  fi

  if [ "$VERBOSE" = "true" ]; then
    echo "Uninstalling updates for ${#TARGET_VM_IDS[@]} VM(s) running windows"
  fi

  for TARGET_VM_ID in "${TARGET_VM_IDS[@]}"; do
    if [ "$VERBOSE" = "true" ]; then
      echo "Uninstalling updates for $TARGET_VM_ID"
    fi
    uninstall_windows_updates "$TARGET_VM_ID" "$KB"
  done
}

if [ -z "$MODE" ]; then
  echo "Error: No mode specified"
  exit 1
fi

if [ "$MODE" != "check" ] && [ "$MODE" != "list-updates" ] && [ "$MODE" != "install" ] && [ "$MODE" != "uninstall" ] && [ "$MODE" != "check-and-install" ]; then
  echo "Error: Invalid mode specified"
  exit 1
fi

USER=$(stat -f%Su /dev/console)
USER_ID=$(id -u $USER)

if [ "$VERBOSE" = "true" ]; then
  echo "Using logged in user: $USER"
fi

check_for_requirements

# Check for updates
if [ "$MODE" = "check" ]; then
  check_for_updates
fi

# List updates
if [ "$MODE" = "list-updates" ]; then
  list_updates
fi

# Install updates
if [ "$MODE" = "install" ]; then
  install_updates
fi

# Uninstall updates
if [ "$MODE" = "uninstall" ]; then
  uninstall_updates
fi

# Check if any VM has updates available and install them
# this will run in the background and not wait for the updates to finish
# so it can release the jamf policy lock
if [ "$MODE" = "check-and-install" ]; then
  if [ "$DEBUG" = "true" ]; then
    check_and_install_updates
  else
    (
      check_and_install_updates
    ) &
    disown
  fi
fi
