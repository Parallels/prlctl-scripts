#!/bin/bash

############
# Get BitLocker status from Windows Parallels VMs for the console macOS user.
#
# - Reads BitLocker status from running VMs.
#
# Requirements:
# - prlctl
#
# Usage examples:
# ./get-bitlocker-status.sh
# ./get-bitlocker-status.sh --silent
# ./get-bitlocker-status.sh --vm "Windows 11"
############

set -u

VM_FILTER=""
SILENT="false"
WAIT_SECONDS=15
VERBOSE="false"
PRLCTL_BIN="/usr/local/bin/prlctl"

usage() {
  cat <<'EOF'
Usage:
  ./get-bitlocker-status.sh [--vm "VM Name or UUID"] [--silent] [--verbose]

Description:
  Checks BitLocker status (C: drive) in Windows Parallels VMs for the console macOS user.

Output per VM:
  - <VM Name>: Protection Status: <status>

Optional behavior:
  --silent
    Only check already-running Windows VMs; do not start or resume non-running VMs.

  --verbose
    Print extra diagnostics when status cannot be determined.
EOF
}

wait_for_vm_running() {
  local owner="$1"
  local vm_id="$2"
  local remaining=30

  while [[ "$remaining" -gt 0 ]]; do
    state=$("${PRLCTL_EXEC[@]}" list "$vm_id" -a -i --json 2>/dev/null \
      | awk -F'"' '$2=="State"{print $4; exit}' 2>/dev/null || true)
    if [[ "$state" == "running" ]]; then
      return 0
    fi
    sleep 2
    remaining=$((remaining - 1))
  done

  return 1
}

start_or_resume_vm() {
  local owner="$1"
  local vm_id="$2"
  local vm_state="$3"

  if [[ "$vm_state" == "paused" || "$vm_state" == "suspended" ]]; then
    "${PRLCTL_EXEC[@]}" resume "$vm_id" </dev/null >/dev/null 2>&1
  else
    "${PRLCTL_EXEC[@]}" start "$vm_id" </dev/null >/dev/null 2>&1
  fi
}

resume_if_paused() {
  local owner="$1"
  local vm_id="$2"

  local state
  state=$("${PRLCTL_EXEC[@]}" list "$vm_id" -a -i --json 2>/dev/null \
    | awk -F'"' '$2=="State"{print $4; exit}' 2>/dev/null || true)

  if [[ "$state" == "paused" ]]; then
    "${PRLCTL_EXEC[@]}" resume "$vm_id" </dev/null >/dev/null 2>&1 || true
    if ! wait_for_vm_running "$owner" "$vm_id"; then
      return 1
    fi
  fi

  return 0
}

show_user_dialog() {
  local message="$1"
  if [[ "$(id -u)" == "0" ]]; then
    sudo -u "$owner" osascript -e "display dialog \"$message\" buttons {\"OK\"} default button \"OK\" with title \"Parallels Desktop\"" >/dev/null 2>&1 || true
  else
    osascript -e "display dialog \"$message\" buttons {\"OK\"} default button \"OK\" with title \"Parallels Desktop\"" >/dev/null 2>&1 || true
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vm)
      VM_FILTER="$2"
      shift 2
      ;;
    --silent)
      SILENT="true"
      shift
      ;;
    -v|--verbose)
      VERBOSE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v "$PRLCTL_BIN" >/dev/null 2>&1; then
  if command -v prlctl >/dev/null 2>&1; then
    PRLCTL_BIN="$(command -v prlctl)"
  else
    echo "Error: prlctl is not installed"
    exit 1
  fi
fi

HOST_USER=$(stat -f%Su /dev/console)
owner="$HOST_USER"

# When running as root (e.g. via MDM), sudo to the console user.
# When already running as the console user, invoke prlctl directly.
if [[ "$(id -u)" == "0" ]]; then
  PRLCTL_EXEC=(sudo -u "$owner" "$PRLCTL_BIN")
else
  PRLCTL_EXEC=("$PRLCTL_BIN")
fi

found_any=false

VMS_DATA=$("${PRLCTL_EXEC[@]}" list -a -i --json 2>/dev/null \
    | awk -F'"' -v vm_filter="$VM_FILTER" '
    /\{[[:space:]]*$/  { depth++; if (depth==1) { id=""; name=""; state=""; os="" }; next }
    /^[[:space:]]*\},?[[:space:]]*$/ {
      if (depth==1 && os=="win-11" && (vm_filter=="" || name==vm_filter || id==vm_filter)) print id "\t" name "\t" state
      depth--; next
    }
    depth!=1  { next }
    $2=="ID"    { id=$4 }
    $2=="Name"  { name=$4 }
    $2=="State" { state=$4 }
    $2=="OS"    { os=$4 }
' || true)

if [[ -n "$VMS_DATA" ]]; then
  found_any=true

  if [[ "$SILENT" != "true" ]]; then
    show_user_dialog "The IT administrator is checking important information about your Parallels virtual machines. They may need to start temporarily."
  fi

  while IFS= read -r vm_line || [[ -n "$vm_line" ]]; do
    vm_id=$(echo "$vm_line" | cut -f1)
    vm_name=$(echo "$vm_line" | cut -f2)
    vm_state=$(echo "$vm_line" | cut -f3)
    [[ -z "$vm_id" ]] && continue

    started_for_check="false"
    if [[ "$vm_state" != "running" ]]; then
      if [[ "$SILENT" == "true" ]]; then
        echo "$vm_name: BitLocker status not available (VM not running)"
        continue
      fi

      start_or_resume_vm "$owner" "$vm_id" "$vm_state"
      if ! wait_for_vm_running "$owner" "$vm_id"; then
        echo "$vm_name: Unable to determine BitLocker status"
        continue
      fi

      sleep "$WAIT_SECONDS"
      if ! resume_if_paused "$owner" "$vm_id"; then
        echo "$vm_name: Unable to determine BitLocker status"
        continue
      fi
      started_for_check="true"
    fi

    output=$("${PRLCTL_EXEC[@]}" exec "$vm_id" cmd /C "manage-bde -status C:" </dev/null 2>&1 || true)
    protection_status=$(echo "$output" | tr -d '\r' | awk -F': *' '/Protection Status:/{print $2; exit}' || true)

    if [[ -n "$protection_status" ]]; then
      echo "$vm_name: Protection Status: $protection_status"
    else
      echo "$vm_name: Unable to determine BitLocker status"
      if [[ "$VERBOSE" == "true" ]]; then
        echo "$vm_name: raw output:"
        echo "$output"
      fi
    fi

    if [[ "$started_for_check" == "true" ]]; then
      "${PRLCTL_EXEC[@]}" suspend "$vm_id" </dev/null >/dev/null 2>&1 || true
    fi
  done <<< "$VMS_DATA"

  if [[ "$SILENT" != "true" ]]; then
    show_user_dialog "The IT administrator has finished checking the Parallels virtual machines. Thank you for your patience."
  fi
fi

if [[ "$found_any" == "false" ]]; then
  if [[ "$SILENT" != "true" ]]; then
    echo "No Windows VMs found"
  else
    echo "No running Windows VMs found"
  fi
fi