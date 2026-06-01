#!/bin/bash

############
# Update SecureBoot PK certificates in Windows 11 Parallels VMs.
#
# Reads the PK certificate hash from VmInfo.pvi (written by Parallels Tools >= 26.3.3).
#
# For VMs where VmInfo.pvi has no hash (Parallels Tools need updating):
# - Shows a dialog to the console user before making any changes
# - Starts the VM if it is not running (skipped when --silent)
# - Issues prlctl installtools to trigger a Parallels Tools update
#
# For VMs with an outdated hash:
# - Shows a dialog to the console user before making any changes
# - Starts the VM if it is not running (skipped when --silent)
# - Suspends BitLocker if active, to prevent a lockout after the reboot
# - Triggers a Windows restart to apply the certificate update
# - Polls VmInfo.pvi until the PK hash confirms the update succeeded
#
# Requirements:
# - Parallels Desktop >= 26.3.3
#
# Usage examples:
# ./update-secureboot-certificates.sh
# ./update-secureboot-certificates.sh --silent
# ./update-secureboot-certificates.sh --vm "Windows 11"
############

set -u

PRLCTL_BIN="/usr/local/bin/prlctl"
MIN_PD_VERSION="26.3.3"
OUTDATED_PK_HASH="7ec69a1bd679fb7aa7b22ce6b3d0204113b19591db1f1d52014022d8c74f0d53"
WAIT_AFTER_START=15
WAIT_RESTART_POLL_INTERVAL=15
WAIT_RESTART_TIMEOUT=300
DRIVE_LETTER="C:"
VM_FILTER=""
SILENT="false"
VERBOSE="false"
PD_VERSION=""

usage() {
  cat <<'EOF'
Usage:
  ./update-secureboot-certificates.sh [--vm "VM Name or UUID"] [--silent] [--verbose]

Description:
  Inspects each Windows 11 VM belonging to the console user and takes one of two
  actions depending on the state of Parallels Tools:

  A) Parallels Tools need updating (no PK hash in VmInfo.pvi):
    1. Starts the VM if not running (skipped when --silent)
    2. Issues prlctl installtools to trigger a Parallels Tools update inside Windows
    Note: the VM is left running so the installer can complete inside Windows.
          Re-run this script after Tools are updated to proceed with the certificate
          update.

  B) Parallels Tools are current but the PK certificate hash is outdated:
    1. Starts the VM if not running (skipped when --silent)
    2. Suspends BitLocker if active (prevents lockout on reboot)
    3. Restarts Windows to apply the certificate update
    4. Confirms success by polling VmInfo.pvi for a non-outdated PK hash

Output per VM:
  <VM Name>: Parallels Tools installation triggered
  <VM Name>: Parallels Tools are not updated yet — VM is not running (use without --silent to install tools)
  <VM Name>: Certificates are up to date
  <VM Name>: Certificate updated successfully
  <VM Name>: ERROR — <reason>

Exit codes:
  0 = Script completed (individual VM errors are reported inline)
  1 = Fatal prerequisite failure
EOF
}

# Jamf Pro prepends mount point, computer name, and username as the first 3 parameters
if [[ "${1:-}" == "/" ]]; then
  shift 3
fi

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

log_verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo "$1"
  fi
}

check_for_requirements() {
  if ! command -v "$PRLCTL_BIN" >/dev/null 2>&1; then
    if command -v prlctl >/dev/null 2>&1; then
      PRLCTL_BIN="$(command -v prlctl)"
    else
      echo "Error: prlctl is not installed"
      exit 1
    fi
  fi
}

get_parallels_version() {
  local version_output
  local version_value

  version_output=$("$PRLCTL_BIN" --version 2>/dev/null || true)
  version_value=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

  if [[ -z "$version_value" ]]; then
    echo "Error: Unable to determine Parallels Desktop version from: $version_output"
    exit 1
  fi

  PD_VERSION="$version_value"
}

version_gte() {
  local IFS='.'
  local -a a b
  read -r -a a <<< "$1"
  read -r -a b <<< "$2"
  local i
  for i in 0 1 2; do
    (( ${a[$i]:-0} > ${b[$i]:-0} )) && return 0
    (( ${a[$i]:-0} < ${b[$i]:-0} )) && return 1
  done
  return 0
}

enforce_parallels_version_gate() {
  if ! version_gte "$PD_VERSION" "$MIN_PD_VERSION"; then
    echo "Error: Parallels Desktop is not updated to $MIN_PD_VERSION (current: $PD_VERSION)"
    exit 1
  fi
}

wait_for_vm_running() {
  local vm_id="$1"
  local remaining=30

  while [[ "$remaining" -gt 0 ]]; do
    local state
    state=$(sudo -u "$HOST_USER" "$PRLCTL_BIN" list "$vm_id" -a -i --json 2>/dev/null \
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
  local vm_id="$1"
  local vm_state="$2"

  if [[ "$vm_state" == "paused" || "$vm_state" == "suspended" ]]; then
    sudo -u "$HOST_USER" "$PRLCTL_BIN" resume "$vm_id" </dev/null >/dev/null 2>&1
  else
    sudo -u "$HOST_USER" "$PRLCTL_BIN" start "$vm_id" </dev/null >/dev/null 2>&1
  fi
}

suspend_vm() {
  local vm_id="$1"
  sudo -u "$HOST_USER" "$PRLCTL_BIN" suspend "$vm_id" </dev/null >/dev/null 2>&1 || true
}

# Resume the VM if Parallels auto-paused it during the settle wait, then confirm
# it reaches running state before continuing.
resume_if_paused() {
  local vm_id="$1"
  local vm_name="$2"

  local state
  state=$(sudo -u "$HOST_USER" "$PRLCTL_BIN" list "$vm_id" -a -i --json 2>/dev/null \
    | awk -F'"' '$2=="State"{print $4; exit}' 2>/dev/null || true)

  if [[ "$state" == "paused" ]]; then
    log_verbose "$vm_name: VM auto-paused, resuming"
    sudo -u "$HOST_USER" "$PRLCTL_BIN" resume "$vm_id" </dev/null >/dev/null 2>&1 || true
    if ! wait_for_vm_running "$vm_id"; then
      return 1
    fi
  fi

  return 0
}

get_pk_hash() {
  local vm_home="$1"
  local pvi_path="${vm_home}VmInfo.pvi"

  if [[ ! -f "$pvi_path" ]]; then
    echo ""
    return
  fi

  grep -o '<UefiPlatformKeySha256>[^<]*</UefiPlatformKeySha256>' "$pvi_path" 2>/dev/null \
    | sed 's/<[^>]*>//g' | tr -d '[:space:]'
}

show_dialog() {
  local message="$1"
  local title="${2:-Security Update}"

  local err
  err=$(launchctl asuser "$USER_ID" /usr/bin/osascript \
    -e "display dialog \"${message}\" buttons {\"OK\"} default button \"OK\" with title \"${title}\" with icon caution" 2>&1)
  if [[ -n "$err" ]]; then
    log_verbose "Dialog error: $err"
  fi
}

get_bitlocker_protection_status() {
  local vm_id="$1"
  local output
  local protection_status

  output=$(sudo -u "$HOST_USER" "$PRLCTL_BIN" exec "$vm_id" cmd /C \
    "manage-bde -status $DRIVE_LETTER" </dev/null 2>&1 || true)
  protection_status=$(echo "$output" | tr -d '\r' \
    | awk -F': *' '/Protection Status:/{print $2; exit}' || true)

  case "$(echo "$protection_status" | tr '[:upper:]' '[:lower:]' | tr -d ' ')" in
    protectionon)  echo "on" ;;
    protectionoff) echo "off" ;;
    *)             echo "unknown" ;;
  esac
}

suspend_bitlocker() {
  local vm_id="$1"
  sudo -u "$HOST_USER" "$PRLCTL_BIN" exec "$vm_id" cmd /C \
    "manage-bde -protectors -disable $DRIVE_LETTER -RebootCount 1" \
    </dev/null >/dev/null 2>&1 || true
}

restart_windows() {
  local vm_id="$1"
  sudo -u "$HOST_USER" "$PRLCTL_BIN" exec "$vm_id" cmd /C \
    "shutdown /r /t 0 /f" \
    </dev/null >/dev/null 2>&1 || true
}

wait_for_cert_update() {
  local vm_home="$1"
  local vm_name="$2"
  local elapsed=0

  log_verbose "$vm_name: Waiting for certificate update (polling every ${WAIT_RESTART_POLL_INTERVAL}s, timeout ${WAIT_RESTART_TIMEOUT}s)"

  while [[ "$elapsed" -lt "$WAIT_RESTART_TIMEOUT" ]]; do
    sleep "$WAIT_RESTART_POLL_INTERVAL"
    elapsed=$((elapsed + WAIT_RESTART_POLL_INTERVAL))

    local hash
    hash=$(get_pk_hash "$vm_home")

    if [[ -z "$hash" ]]; then
      log_verbose "$vm_name: Hash not yet present in VmInfo.pvi (${elapsed}s elapsed)"
      continue
    fi

    if [[ "$hash" == "$OUTDATED_PK_HASH" ]]; then
      log_verbose "$vm_name: Hash still outdated (${elapsed}s elapsed)"
      continue
    fi

    log_verbose "$vm_name: Hash updated to $hash after ${elapsed}s"
    return 0
  done

  return 1
}

# ─── Main ─────────────────────────────────────────────────────────────────────

check_for_requirements
get_parallels_version
enforce_parallels_version_gate

HOST_USER=$(stat -f%Su /dev/console)
if [[ -z "$HOST_USER" || "$HOST_USER" == "root" || "$HOST_USER" == "loginwindow" ]]; then
  echo "No console user logged in"
  exit 0
fi
USER_ID=$(id -u "$HOST_USER")

log_verbose "Console user: $HOST_USER (uid $USER_ID)"
log_verbose "Parallels Desktop version: $PD_VERSION"

VMS_DATA=$(sudo -u "$HOST_USER" "$PRLCTL_BIN" list -a -i --json 2>/dev/null \
  | awk -F'"' -v vm_filter="$VM_FILTER" '
    /\{[[:space:]]*$/  { depth++; if (depth==1) { id=""; name=""; state=""; os=""; home="" }; next }
    /^[[:space:]]*\},?[[:space:]]*$/ {
      if (depth==1 && os=="win-11" && (vm_filter=="" || name==vm_filter || id==vm_filter)) { gsub(/\\/, "", home); print id "\t" name "\t" state "\t" home }
      depth--; next
    }
    depth!=1  { next }
    $2=="ID"    { id=$4 }
    $2=="Name"  { name=$4 }
    $2=="State" { state=$4 }
    $2=="OS"    { os=$4 }
    $2=="Home"  { home=$4 }
' || true)

if [[ -z "$VMS_DATA" ]]; then
  echo "No Windows 11 VMs found"
  exit 0
fi

# ── Phase 1: classify VMs ──────────────────────────────────────────────────────

update_list=$(mktemp /tmp/pk-update-list.XXXXXX)
tools_list=$(mktemp /tmp/pk-tools-list.XXXXXX)
trap 'rm -f "$update_list" "$tools_list"' EXIT

while IFS=$'\t' read -r vm_id vm_name vm_state vm_home || [[ -n "$vm_id" ]]; do
  [[ -n "$vm_id" ]] || continue

  log_verbose "Checking '$vm_name' ($vm_id)"

  pk_hash=$(get_pk_hash "$vm_home")

  if [[ -z "$pk_hash" ]]; then
    log_verbose "$vm_name: Parallels Tools are not updated yet, queued for tools install"
    printf '%s\t%s\t%s\t%s\n' "$vm_id" "$vm_name" "$vm_state" "$vm_home" >> "$tools_list"
    continue
  fi

  if [[ "$pk_hash" != "$OUTDATED_PK_HASH" ]]; then
    echo "$vm_name: Certificates are up to date"
    continue
  fi

  log_verbose "$vm_name: PK hash is outdated, queued for update"
  printf '%s\t%s\t%s\t%s\n' "$vm_id" "$vm_name" "$vm_state" "$vm_home" >> "$update_list"
done <<< "$VMS_DATA"

if [[ ! -s "$update_list" && ! -s "$tools_list" ]]; then
  exit 0
fi

# ── Phase 2: notify console user before touching any VM ───────────────────────

NOTIFICATION_SHOWN="false"
show_dialog \
  "Windows VM(s) might require a security update. This update is initiated by your IT department. Windows might restart during this update." \
  "Security Update"
NOTIFICATION_SHOWN="true"
log_verbose "Dialog shown to $HOST_USER"

# ── Phase 3: install Parallels Tools ──────────────────────────────────────────

if [[ -s "$tools_list" ]]; then
  while IFS=$'\t' read -r vm_id vm_name vm_state vm_home; do
    [[ -n "$vm_id" ]] || continue

    log_verbose "Installing Parallels Tools on '$vm_name' ($vm_id) — state: $vm_state"

    if [[ "$vm_state" != "running" ]]; then
      if [[ "$SILENT" == "true" ]]; then
        echo "$vm_name: Parallels Tools are not updated yet — VM is not running (use without --silent to install tools)"
        continue
      fi

      log_verbose "$vm_name: Starting VM from state '$vm_state'"
      start_or_resume_vm "$vm_id" "$vm_state"
      if ! wait_for_vm_running "$vm_id"; then
        echo "$vm_name: ERROR — VM did not reach running state for tools install"
        continue
      fi

      log_verbose "$vm_name: Waiting ${WAIT_AFTER_START}s for VM to settle"
      sleep "$WAIT_AFTER_START"
      if ! resume_if_paused "$vm_id" "$vm_name"; then
        echo "$vm_name: ERROR — VM did not return to running state after auto-pause"
        continue
      fi
      started_for_tools="true"
    fi

    log_verbose "$vm_name: Issuing installtools command"
    sudo -u "$HOST_USER" "$PRLCTL_BIN" installtools "$vm_id" </dev/null >/dev/null 2>&1 || true
    echo "$vm_name: Parallels Tools installation triggered"

  done < "$tools_list"
fi

# ── Phase 4: certificate update loop ──────────────────────────────────────────

SUCCESS_COUNT=0

while IFS=$'\t' read -r vm_id vm_name vm_state vm_home; do
  [[ -n "$vm_id" ]] || continue

  log_verbose "Processing '$vm_name' ($vm_id) — state: $vm_state"

  started_for_action="false"
  if [[ "$vm_state" != "running" ]]; then
    if [[ "$SILENT" == "true" ]]; then
      echo "$vm_name: VM is not running (use without --silent to process non-running VMs)"
      continue
    fi

    log_verbose "$vm_name: Starting VM from state '$vm_state'"
    start_or_resume_vm "$vm_id" "$vm_state"
    if ! wait_for_vm_running "$vm_id"; then
      echo "$vm_name: ERROR — VM did not reach running state"
      continue
    fi

    log_verbose "$vm_name: Waiting ${WAIT_AFTER_START}s for VM to settle"
    sleep "$WAIT_AFTER_START"
    if ! resume_if_paused "$vm_id" "$vm_name"; then
      echo "$vm_name: ERROR — VM did not return to running state after auto-pause"
      continue
    fi
    started_for_action="true"
  fi

  # Check BitLocker before restarting to avoid a potential lockout
  log_verbose "$vm_name: Checking BitLocker status on $DRIVE_LETTER"
  bitlocker_status=$(get_bitlocker_protection_status "$vm_id")
  log_verbose "$vm_name: BitLocker protection: $bitlocker_status"

  if [[ "$bitlocker_status" == "unknown" ]]; then
    echo "$vm_name: ERROR — Could not determine BitLocker status; skipping restart to avoid lockout"
    if [[ "$started_for_action" == "true" ]]; then
      suspend_vm "$vm_id"
    fi
    continue
  fi

  if [[ "$bitlocker_status" == "on" ]]; then
    log_verbose "$vm_name: Suspending BitLocker for one reboot"
    suspend_bitlocker "$vm_id"
  fi

  # Restart Windows to trigger the certificate update
  log_verbose "$vm_name: Triggering Windows restart"
  restart_windows "$vm_id"
  sleep 5  # allow Windows to begin shutting down before polling VmInfo.pvi

  # Poll VmInfo.pvi until the hash reflects the updated certificate
  if wait_for_cert_update "$vm_home" "$vm_name"; then
    echo "$vm_name: Certificate updated successfully"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "$vm_name: ERROR — Certificate update not confirmed after ${WAIT_RESTART_TIMEOUT}s"
  fi

  if [[ "$started_for_action" == "true" ]]; then
    log_verbose "$vm_name: Suspending VM after update"
    suspend_vm "$vm_id"
  fi

done < "$update_list"

# ── Phase 5: completion notification ──────────────────────────────────────────

if [[ "$NOTIFICATION_SHOWN" == "true" && "$SUCCESS_COUNT" -gt 0 ]]; then
  show_dialog \
    "The security certificate update for your Windows VM(s) has been completed successfully." \
    "Security Update Complete"
fi

exit 0
