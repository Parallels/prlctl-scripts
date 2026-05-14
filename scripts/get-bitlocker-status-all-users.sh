#!/bin/bash

############
# Get BitLocker status from Windows Parallels VMs across all macOS users.
#
# Designed for Mac MDM execution at scale:
# - Runs as root/system context.
# - Enumerates Windows VMs for all local users.
# - Reads BitLocker status from running VMs.
# - Returns structured output (text/json/csv) plus a summary line.
#
# Requirements:
# - prlctl
# - jq (or script can download a temporary jq binary to /tmp)
#
# Usage examples:
# ./get-bitlocker-status-all-users.sh
# ./get-bitlocker-status-all-users.sh --format json
# ./get-bitlocker-status-all-users.sh --vm-id "<UUID>" --format csv
############

set -u

FORMAT="text"
VM_FILTER=""
VERBOSE="false"
JQ_BIN="jq"
PRLCTL_BIN="/usr/local/bin/prlctl"
FORCE_NON_RUNNING="false"
WAIT_SECONDS=60

TEMP_FILES=()

function cleanup() {
  for f in "${TEMP_FILES[@]:-}"; do
    if [ -n "$f" ] && [ -f "$f" ]; then
      rm -f "$f"
    fi
  done
}

trap cleanup EXIT

function show_help() {
  echo "Parallels Windows VM BitLocker Status Script (All Users)"
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  -f, --format FORMAT   Output format: text (default), json, csv"
  echo "  -i, --vm-id ID        Target a specific VM ID or VM Name"
  echo "  -r, --run-non-running Start non-running VMs, wait, check BitLocker, then suspend them again"
  echo "  -v, --verbose         Enable verbose logging"
  echo "  -h, --help            Show this help message"
  echo
  echo "Exit behavior:"
  echo "  0 = Script executed (even if some VMs return errors/skipped)"
  echo "  1 = Missing prerequisites or fatal script error"
}

while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
  -f | --format)
    FORMAT="$2"
    shift
    shift
    ;;
  -i | --vm-id)
    VM_FILTER="$2"
    shift
    shift
    ;;
  -r | --run-non-running)
    FORCE_NON_RUNNING="true"
    shift
    ;;
  -v | --verbose)
    VERBOSE="true"
    shift
    ;;
  -h | --help)
    show_help
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    show_help
    exit 1
    ;;
  esac
done

function log_verbose() {
  if [ "$VERBOSE" = "true" ]; then
    echo "$1"
  fi
}

function wait_for_vm_running() {
  local owner="$1"
  local vm_id="$2"
  local remaining=30

  while [ "$remaining" -gt 0 ]; do
    current_state=$(sudo -u "$owner" "$PRLCTL_BIN" list "$vm_id" -a -i --json 2>/dev/null | "$JQ_BIN" -r '.[0].State // empty')
    if [ "$current_state" = "running" ]; then
      return 0
    fi
    sleep 2
    remaining=$((remaining - 1))
  done

  return 1
}

function start_or_resume_vm() {
  local owner="$1"
  local vm_id="$2"
  local vm_state="$3"

  if [ "$vm_state" = "running" ]; then
    return 0
  fi

  if [ "$vm_state" = "paused" ] || [ "$vm_state" = "suspended" ]; then
    sudo -u "$owner" "$PRLCTL_BIN" resume "$vm_id" >/dev/null 2>&1
  else
    sudo -u "$owner" "$PRLCTL_BIN" start "$vm_id" >/dev/null 2>&1
  fi
}

function suspend_vm() {
  local owner="$1"
  local vm_id="$2"

  sudo -u "$owner" "$PRLCTL_BIN" suspend "$vm_id" >/dev/null 2>&1
}

function check_for_requirements() {
  if ! command -v "$PRLCTL_BIN" >/dev/null 2>&1; then
    if command -v prlctl >/dev/null 2>&1; then
      PRLCTL_BIN="$(command -v prlctl)"
    else
      echo "Error: prlctl is not installed"
      exit 1
    fi
  fi

  if command -v jq >/dev/null 2>&1; then
    JQ_BIN="$(command -v jq)"
    return
  fi

  JQ_BIN="/tmp/jq"
  if [ -f "$JQ_BIN" ]; then
    return
  fi

  log_verbose "jq not found. Downloading temporary jq binary to /tmp/jq"

  ARCH="$(uname -m)"
  JQ_URL=""
  if [ "$ARCH" = "arm64" ]; then
    JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-arm64"
  elif [ "$ARCH" = "x86_64" ]; then
    JQ_URL="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-amd64"
  else
    echo "Error: Unsupported architecture '$ARCH' for automatic jq download"
    exit 1
  fi

  if ! curl -Ls -o "$JQ_BIN" "$JQ_URL"; then
    echo "Error: Failed to download jq"
    exit 1
  fi

  chmod +x "$JQ_BIN"
  xattr -dr com.apple.quarantine "$JQ_BIN" >/dev/null 2>&1 || true
}

function get_host_users() {
  dscl . list /Users | grep -v "^_" | grep '\S'
}

function append_record() {
  local results_file="$1"
  local owner="$2"
  local vm_id="$3"
  local vm_name="$4"
  local vm_state="$5"
  local tools_state="$6"
  local collection_status="$7"
  local protection_status="$8"
  local encryption_percentage="$9"
  local volume_status="${10}"
  local encryption_method="${11}"
  local lock_status="${12}"
  local message="${13}"

  "$JQ_BIN" -cn \
    --arg owner "$owner" \
    --arg vmId "$vm_id" \
    --arg vmName "$vm_name" \
    --arg vmState "$vm_state" \
    --arg toolsState "$tools_state" \
    --arg collectionStatus "$collection_status" \
    --arg protectionStatus "$protection_status" \
    --arg encryptionPercentage "$encryption_percentage" \
    --arg volumeStatus "$volume_status" \
    --arg encryptionMethod "$encryption_method" \
    --arg lockStatus "$lock_status" \
    --arg message "$message" \
    '{
      owner: $owner,
      vmId: $vmId,
      vmName: $vmName,
      vmState: $vmState,
      toolsState: $toolsState,
      collectionStatus: $collectionStatus,
      protectionStatus: $protectionStatus,
      encryptionPercentage: $encryptionPercentage,
      volumeStatus: $volumeStatus,
      encryptionMethod: $encryptionMethod,
      lockStatus: $lockStatus,
      message: $message
    }' >>"$results_file"
}

function collect_bitlocker_status() {
  local results_file="$1"

  for owner in $(get_host_users); do
    [ -n "$owner" ] || continue
    [ -d "/Users/$owner" ] || continue

    log_verbose "Checking VMs for macOS user: $owner"
    vm_json=$(sudo -u "$owner" "$PRLCTL_BIN" list -a -i --json 2>/dev/null)
    if [ -z "$vm_json" ] || [ "$vm_json" = "[]" ]; then
      continue
    fi

    if [ -n "$VM_FILTER" ]; then
      vm_lines=$(echo "$vm_json" | "$JQ_BIN" -rc --arg vmFilter "$VM_FILTER" '
        .[]
        | select((.OS == "win-10" or .OS == "win-11") and (.ID == $vmFilter or .Name == $vmFilter))
        | {id:.ID, name:.Name, state:.State, tools_state:.GuestTools.state}
      ')
    else
      vm_lines=$(echo "$vm_json" | "$JQ_BIN" -rc '
        .[]
        | select(.OS == "win-10" or .OS == "win-11")
        | {id:.ID, name:.Name, state:.State, tools_state:.GuestTools.state}
      ')
    fi
    if [ -z "$vm_lines" ]; then
      continue
    fi

    while IFS= read -r vm; do
      [ -n "$vm" ] || continue
      vm_id=$(echo "$vm" | "$JQ_BIN" -r '.id')
      vm_name=$(echo "$vm" | "$JQ_BIN" -r '.name')
      vm_state=$(echo "$vm" | "$JQ_BIN" -r '.state')
      tools_state=$(echo "$vm" | "$JQ_BIN" -r '.tools_state // "unknown"')

      log_verbose "Processing VM '$vm_name' ($vm_id) state=$vm_state tools=$tools_state"

      started_for_check="false"
      if [ "$vm_state" != "running" ]; then
        if [ "$FORCE_NON_RUNNING" != "true" ]; then
          append_record "$results_file" "$owner" "$vm_id" "$vm_name" "$vm_state" "$tools_state" "skipped" "unknown" "" "" "" "" "VM is not running"
          continue
        fi

        log_verbose "Starting non-running VM '$vm_name' ($vm_id) from state $vm_state"
        start_or_resume_vm "$owner" "$vm_id" "$vm_state"
        if [ $? -ne 0 ]; then
          append_record "$results_file" "$owner" "$vm_id" "$vm_name" "$vm_state" "$tools_state" "error" "unknown" "" "" "" "" "Failed to start or resume VM"
          continue
        fi

        log_verbose "Waiting $WAIT_SECONDS seconds for VM '$vm_name' ($vm_id) to settle"
        sleep "$WAIT_SECONDS"
        if ! wait_for_vm_running "$owner" "$vm_id"; then
          append_record "$results_file" "$owner" "$vm_id" "$vm_name" "$vm_state" "$tools_state" "error" "unknown" "" "" "" "" "VM did not reach running state"
          continue
        fi

        started_for_check="true"
      fi

      output=$(sudo -u "$owner" "$PRLCTL_BIN" exec "$vm_id" cmd /C "manage-bde -status C:" 2>&1)
      exit_code=$?

      if [ $exit_code -ne 0 ]; then
        error_msg=$(echo "$output" | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^ //;s/ $//')
        [ -n "$error_msg" ] || error_msg="Unable to query BitLocker status"
        append_record "$results_file" "$owner" "$vm_id" "$vm_name" "$vm_state" "$tools_state" "error" "unknown" "" "" "" "" "$error_msg"
        continue
      fi

      protection_status=$(echo "$output" | awk -F': *' '/Protection Status:/{print $2; exit}' | tr -d '\r')
      encryption_percentage=$(echo "$output" | awk -F': *' '/Percentage Encrypted:/{print $2; exit}' | tr -d '\r')
      volume_status=$(echo "$output" | awk -F': *' '/Conversion Status:/{print $2; exit}' | tr -d '\r')
      encryption_method=$(echo "$output" | awk -F': *' '/Encryption Method:/{print $2; exit}' | tr -d '\r')
      lock_status=$(echo "$output" | awk -F': *' '/Lock Status:/{print $2; exit}' | tr -d '\r')

      [ -n "$protection_status" ] || protection_status="unknown"
      [ -n "$encryption_percentage" ] || encryption_percentage=""
      [ -n "$volume_status" ] || volume_status=""
      [ -n "$encryption_method" ] || encryption_method=""
      [ -n "$lock_status" ] || lock_status=""

      append_record "$results_file" "$owner" "$vm_id" "$vm_name" "$vm_state" "$tools_state" "ok" "$protection_status" "$encryption_percentage" "$volume_status" "$encryption_method" "$lock_status" ""

      if [ "$started_for_check" = "true" ]; then
        log_verbose "Suspending VM '$vm_name' ($vm_id) after BitLocker check"
        suspend_vm "$owner" "$vm_id"
      fi
    done <<<"$vm_lines"
  done
}

function print_output() {
  local results_file="$1"
  local results_array_file="$2"

  "$JQ_BIN" -s '.' "$results_file" >"$results_array_file"

  local total ok_count error_count skipped_count protected_count unprotected_count unknown_count
  total=$("$JQ_BIN" 'length' "$results_array_file")
  ok_count=$("$JQ_BIN" '[.[] | select(.collectionStatus == "ok")] | length' "$results_array_file")
  error_count=$("$JQ_BIN" '[.[] | select(.collectionStatus == "error")] | length' "$results_array_file")
  skipped_count=$("$JQ_BIN" '[.[] | select(.collectionStatus == "skipped")] | length' "$results_array_file")
  protected_count=$("$JQ_BIN" '[.[] | select(.collectionStatus == "ok" and (.protectionStatus | test("Protection On")))] | length' "$results_array_file")
  unprotected_count=$("$JQ_BIN" '[.[] | select(.collectionStatus == "ok" and (.protectionStatus | test("Protection Off")))] | length' "$results_array_file")
  unknown_count=$("$JQ_BIN" '[.[] | select(.collectionStatus == "ok" and ((.protectionStatus | test("Protection On")) | not) and ((.protectionStatus | test("Protection Off")) | not))] | length' "$results_array_file")

  case "$FORMAT" in
  "json")
    "$JQ_BIN" -cn \
      --argjson records "$(cat "$results_array_file")" \
      --argjson total "$total" \
      --argjson ok "$ok_count" \
      --argjson errors "$error_count" \
      --argjson skipped "$skipped_count" \
      --argjson protected "$protected_count" \
      --argjson unprotected "$unprotected_count" \
      --argjson unknown "$unknown_count" \
      '{
        summary: {
          total: $total,
          ok: $ok,
          errors: $errors,
          skipped: $skipped,
          protected: $protected,
          unprotected: $unprotected,
          unknown: $unknown
        },
        records: $records
      }'
    ;;
  "csv")
    "$JQ_BIN" -r '
      [
        "owner",
        "vmId",
        "vmName",
        "vmState",
        "toolsState",
        "collectionStatus",
        "protectionStatus",
        "encryptionPercentage",
        "volumeStatus",
        "encryptionMethod",
        "lockStatus",
        "message"
      ],
      (
        .[] | [
          .owner,
          .vmId,
          .vmName,
          .vmState,
          .toolsState,
          .collectionStatus,
          .protectionStatus,
          .encryptionPercentage,
          .volumeStatus,
          .encryptionMethod,
          .lockStatus,
          .message
        ]
      ) | @csv
    ' "$results_array_file"

    ;;
  "text")
    if [ "$ok_count" -gt 0 ]; then
      "$JQ_BIN" -r '.[] | select(.collectionStatus == "ok") | "    Protection Status:    " + .protectionStatus' "$results_array_file"
    elif [ "$skipped_count" -gt 0 ] && [ "$error_count" -eq 0 ]; then
      echo "Windows VM(s) are not running"
    elif [ "$error_count" -gt 0 ]; then
      echo "Windows VM(s) are running but BitLocker status query failed"
    else
      echo "No Windows VMs found"
    fi
    ;;
  *)
    echo "Error: Unsupported format '$FORMAT'. Use text, json, or csv."
    exit 1
    ;;
  esac
}

check_for_requirements

results_file=$(mktemp /tmp/bitlocker-status-records.XXXXXX)
results_array_file=$(mktemp /tmp/bitlocker-status-array.XXXXXX)
TEMP_FILES+=("$results_file")
TEMP_FILES+=("$results_array_file")

collect_bitlocker_status "$results_file"

if [ ! -s "$results_file" ]; then
  if [ "$FORMAT" = "json" ]; then
    echo '{"summary":{"total":0,"ok":0,"errors":0,"skipped":0,"protected":0,"unprotected":0,"unknown":0},"records":[]}'
  elif [ "$FORMAT" = "csv" ]; then
    echo "owner,vmId,vmName,vmState,toolsState,collectionStatus,protectionStatus,encryptionPercentage,volumeStatus,encryptionMethod,lockStatus,message"
  else
    echo "No Windows VMs found"
  fi
  exit 0
fi

print_output "$results_file" "$results_array_file"
exit 0
