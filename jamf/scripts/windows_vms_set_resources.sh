#!/bin/bash

############

# Set CPU and Memory of Windows VMs
#
# This script sets the number of CPU cores and the amount of memory (RAM) of
# the Windows virtual machines of the logged in user in Parallels Desktop.
# It can be pushed from a Mac management tool that runs scripts as root.
#
# The settings can only be changed while a VM is stopped. VMs that are not
# stopped are skipped, and are updated the next time the script runs.
#
# Requirements:
# - prlctl
#
# Jamf Pro parameters (optional, they override the values below):
#   Parameter 4: Memory in MB (for example 8192 for 8 GB)
#   Parameter 5: CPU cores
#   Parameter 6: VM name or ID (leave empty to target all Windows VMs)
#

# Configuration
MEMORY_MB="8192"
CPU_COUNT="4"
TARGET_VM_ID=""

if [ -n "${4:-}" ]; then MEMORY_MB="$4"; fi
if [ -n "${5:-}" ]; then CPU_COUNT="$5"; fi
if [ -n "${6:-}" ]; then TARGET_VM_ID="$6"; fi

PRLCTL="prlctl"
USER=""
HAS_ERRORS="false"

function check_for_requirements() {
  if ! which prlctl >/dev/null 2>&1; then
    PRLCTL="/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"
    if [ ! -x "$PRLCTL" ]; then
      echo "Error: prlctl is not installed"
      exit 1
    fi
  fi

  case "$MEMORY_MB" in
  '' | *[!0-9]* | 0)
    echo "Error: MEMORY_MB must be a positive whole number of MB (got '$MEMORY_MB')"
    exit 1
    ;;
  esac

  case "$CPU_COUNT" in
  '' | *[!0-9]* | 0)
    echo "Error: CPU_COUNT must be a positive whole number (got '$CPU_COUNT')"
    exit 1
    ;;
  esac
}

function list_vms() {
  if [ -n "$TARGET_VM_ID" ]; then
    echo "$TARGET_VM_ID"
  else
    sudo -u "$USER" "$PRLCTL" list -a -o uuid,ostype | awk '/win/ {print $1}'
  fi
}

function get_vm_state() {
  VM_ID=$1

  sudo -u "$USER" "$PRLCTL" list "$VM_ID" -a -o status | tail -n 1 | tr -d ' '
}

function set_vm_resources() {
  VM_ID=$1

  VM_STATE=$(get_vm_state "$VM_ID")
  if [ "$VM_STATE" != "stopped" ]; then
    echo "Skipping $VM_ID because it is $VM_STATE and must be stopped first"
    return 0
  fi

  echo "Setting $VM_ID to $MEMORY_MB MB of memory and $CPU_COUNT CPU cores"
  sudo -u "$USER" "$PRLCTL" set "$VM_ID" --memsize "$MEMORY_MB" --cpus "$CPU_COUNT"
  last_exit_code=$?
  if [ $last_exit_code -ne 0 ]; then
    echo "Error: Failed to set resources for VM $VM_ID"
    HAS_ERRORS="true"
    return 1
  fi

  sudo -u "$USER" "$PRLCTL" list -i "$VM_ID" | grep -E '^[[:space:]]*(cpu|memory)[[:space:]]'
}

USER=$(stat -f%Su /dev/console)
if [ -z "$USER" ] || [ "$USER" = "root" ] || [ "$USER" = "loginwindow" ]; then
  echo "No user is currently logged in, nothing to do"
  exit 0
fi

check_for_requirements

echo "Using logged in user: $USER"

VM_COUNT=0
while IFS= read -r VM; do
  [ -z "$VM" ] && continue
  VM_COUNT=$((VM_COUNT + 1))
  set_vm_resources "$VM"
done < <(list_vms)

if [ $VM_COUNT -eq 0 ]; then
  echo "No Windows VMs found"
  exit 0
fi

if [ "$HAS_ERRORS" = "true" ]; then
  exit 1
fi

exit 0