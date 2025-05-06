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

MODE="$4"
AUTO_REBOOT="false"
USER_PROMPT="true"
VERBOSE="false"
OUTPUT_FILE=""
TARGET_VM_ID=""
USER=""
USER_ID=""
TARGET_VM_IDS=()
KB=""

# check if the unattended parameter is true
if [ "$5" = "true" ]; then
  USER_PROMPT="false"
fi

# check if the auto reboot parameter is true
if [ "$6" = "true" ]; then
  AUTO_REBOOT="true"
fi

function check_for_requirements() {
  prlctl_installed=$(which prlctl)
  if [[ -z "$prlctl_installed" ]]; then
    echo "prlctl is not installed"
    exit 1
  fi

  # Check if jq is installed
  if [[ ! -f "/tmp/jq" ]]; then
    if [ "$VERBOSE" = "true" ]; then
      echo "jq is not installed. Installing temporary version..."
    fi

    curl -Ls -o /tmp/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-arm64
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
  VMS=$(sudo -u $USER prlctl list -a -i --json | /tmp/jq -r 'map(select((.OS == "win-10" or .OS == "win-11" or .OS=="ubuntu") and .State == "running") | {id:.ID, name: .Name, tools_state: .GuestTools.state})')
  echo "$VMS"
}

function get_list_of_updates() {
  VM_ID=$1

  # Create a temporary file to store the complete output
  temp_output_file=$(mktemp)

  # Execute the command and redirect all output to the temporary file
  sudo -u $USER prlctl exec $VM_ID pwsh -Command "Install-Module PSWindowsUpdate -Force -AllowClobber; Import-Module PSWindowsUpdate; Get-WindowsUpdate | ForEach-Object { \$_ | Select-Object -Property Title,KB,KBArticleIDs,Size,LastDeploymentChangeTime,Status } | ConvertTo-Json -Depth 5" >"$temp_output_file" 2>/dev/null

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
  updates=$(echo "$raw_updates" | /tmp/jq -c -r 'map({title: .Title, kb: .KB, kbArticleIDs: .KBArticleIDs, size: .Size, lastDeploymentChangeTime: .LastDeploymentChangeTime, status: .Status})')

  rm -f "$temp_output_file"
  echo "$updates"
}

function install_windows_updates() {
  VM_ID=$1
  TARGET_KB=$2
  echo "Installing updates for $VM_ID"
  if [ -z "$TARGET_KB" ]; then
    if [ "$AUTO_REBOOT" = "true" ]; then
      RESULT=$(sudo -u $USER prlctl exec $VM_ID pwsh -Command "Install-Module PSWindowsUpdate -Force -AllowClobber; Import-Module PSWindowsUpdate; Install-WindowsUpdate -AcceptAll -AutoReboot | ConvertTo-Json -Depth 5")
    else
      RESULT=$(sudo -u $USER prlctl exec $VM_ID pwsh -Command "Install-Module PSWindowsUpdate -Force -AllowClobber; Import-Module PSWindowsUpdate; Install-WindowsUpdate -AcceptAll | ConvertTo-Json -Depth 5")
    fi
  else
    if [ "$AUTO_REBOOT" = "true" ]; then
      RESULT=$(sudo -u $USER prlctl exec $VM_ID pwsh -Command "Install-Module PSWindowsUpdate -Force -AllowClobber; Import-Module PSWindowsUpdate; Install-WindowsUpdate -KBArticleID $TARGET_KB -AcceptAll -AutoReboot | ConvertTo-Json -Depth 5")
    else
      RESULT=$(sudo -u $USER prlctl exec $VM_ID pwsh -Command "Install-Module PSWindowsUpdate -Force -AllowClobber; Import-Module PSWindowsUpdate; Install-WindowsUpdate -KBArticleID $TARGET_KB -AcceptAll | ConvertTo-Json -Depth 5")
    fi
  fi
  echo "COMPLETE"
}

function uninstall_windows_updates() {
  VM_ID=$1
  TARGET_KB=$2
  RESULT=$(sudo -u $USER prlctl exec $VM_ID pwsh -Command "Install-Module PSWindowsUpdate -Force -AllowClobber; Import-Module PSWindowsUpdate; Uninstall-WindowsUpdate -KBArticleID $TARGET_KB | ConvertTo-Json -Depth 5")
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

  if [ "$VERBOSE" = "true" ]; then
    echo "Update information saved to $output_file"
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
      echo "Checking for updates for $vm_name ($vm_id)"
    fi
    updates=$(get_list_of_updates "$vm_id" "$vm_name")
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
    # Output to stdout with less strict error handling
    printf '%s\n' "${ALL_UPDATES[@]}" | /tmp/jq -s '.' 2>/dev/null || {
      if [ "$VERBOSE" = "true" ]; then
        echo "Warning: Some non-critical errors occurred while formatting JSON output"
      fi
    }
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
      echo "Checking for updates for $vm_name ($vm_id)"
    fi
    updates=$(get_list_of_updates "$vm_id" "$vm_name")
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
    # Output to stdout with less strict error handling
    printf '%s\n' "${ALL_UPDATES[@]}" | /tmp/jq -s '.' 2>/dev/null || {
      if [ "$VERBOSE" = "true" ]; then
        echo "Warning: Some non-critical errors occurred while formatting JSON output"
      fi
    }
  fi
}

function check_and_install_updates() {
  # Check if any VM has updates available
  result=$(list_updates)
  has_updates=$(echo "$result" | /tmp/jq 'map(.updates) | any')

  # setting the auto reboot to true if the script is run unattended
  if [ "$USER_PROMPT" = "false" ]; then
    AUTO_REBOOT="true"
  fi

  if [ "$has_updates" = "true" ]; then
    # Parse the result JSON to get details about which VMs have updates
    if [ "$VERBOSE" = "true" ]; then
      echo "Updates available for the following VMs:"
    fi

    # Iterate through each VM in the result array
    vm_count=$(echo "$result" | /tmp/jq 'length')
    for ((i = 0; i < $vm_count; i++)); do
      vm_name=$(echo "$result" | /tmp/jq -r ".[$i].name")
      vm_id=$(echo "$result" | /tmp/jq -r ".[$i].id")
      has_tools_update=$(echo "$result" | /tmp/jq -r ".[$i].guest_tools" | grep -q "outdated" && echo "true" || echo "false")
      has_vm_updates=$(echo "$result" | /tmp/jq -r ".[$i].updates | length > 0")
      if [ "$has_vm_updates" = "true" ] || [ "$has_tools_update" = "true" ]; then
        list_updates=""
        if [ "$has_tools_update" = "true" ]; then
          list_updates="Parallels Desktop Guest Tools"
        fi

        if [ "$VERBOSE" = "true" ]; then
          update_count=$(echo "$result" | /tmp/jq -r ".[$i].updates | length")
          echo "- $vm_name (ID: $vm_id) has $update_count updates available"

          # List the updates if verbose mode is enabled
          updates=$(echo "$result" | /tmp/jq -r ".[$i].updates")
          echo "$updates" | /tmp/jq -r '.[] | "  * " + .title + " (KB: " + .kb + ")"' 2>/dev/null
        fi

        list_updates="$list_updates\n$(echo "$updates" | /tmp/jq -r '.[].updates | .title' 2>/dev/null)"
        if [ "$VERBOSE" = "true" ]; then
          echo "list_updates: $list_updates"
        fi

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
  display dialog "There are updates available for VM $vm_name.\n$UPDATES_TYPE\n\nDo you want to install them?\n\n⚠️ ATTENTION: the VM might restart during the installation." with title "VM Security Updates" buttons {"Install", "Cancel"} default button "Install"
  return "::Install"
on error errMsg number errNumber
  return "::Cancel"
end try
EOF
          )
          if [ "$response" = "::Cancel" ]; then
            CAN_INSTALL="false"
            exit 0
          fi
          if [ "$response" = "::Install" ]; then
            CAN_INSTALL="true"
          fi
        else
          CAN_INSTALL="true"
        fi

        if [ "$CAN_INSTALL" = "true" ]; then
          if [ "$has_vm_updates" = "true" ]; then
            install_windows_updates "$vm_id" "$KB"
          fi

          #TODO: add a loop to check if the tools finished updating
          # we will have a retry of every 10 seconds with a max of 18 retries, 3 minutes
          # if the tools are not updated in 3 minutes, we will skip the rest of the updates
          # Before this we need to check if the VM is running
          if [ "$has_tools_update" = "true" ]; then
            update_pd_tools "$vm_id"
          fi
        fi
      else
        echo "No updates available for $vm_name ($vm_id)"
      fi
    done
  fi
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
echo "Using logged in user: $USER"
check_for_requirements

if [ "$MODE" = "check" ]; then
  check_for_updates
fi

if [ "$MODE" = "list-updates" ]; then
  list_updates
fi

if [ "$MODE" = "install" ]; then
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
fi

if [ "$MODE" = "uninstall" ]; then
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
fi

# Check if any VM has updates available and install them if so
if [ "$MODE" = "check-and-install" ]; then
  (
    check_and_install_updates
  ) &
  disown
fi
