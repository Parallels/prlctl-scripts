#!/bin/bash

############
# Suspend BitLocker for one reboot on Windows Parallels VMs across all macOS users.
#
# Designed for Mac MDM execution at scale:
# - Runs as root/system context.
# - Enumerates Windows VMs for all local users.
# - Suspends BitLocker protectors for one reboot using manage-bde.
#
# Requirements:
# - prlctl
#
# Usage examples:
# ./suspend-bitlocker-one-reboot-all-users.sh
# ./suspend-bitlocker-one-reboot-all-users.sh --run-non-running
# ./suspend-bitlocker-one-reboot-all-users.sh --vm-id "<UUID or Name>" --format json
############

set -u

FORMAT="text"
VM_FILTER=""
VERBOSE="false"
PRLCTL_BIN="/usr/local/bin/prlctl"
FORCE_NON_RUNNING="false"
WAIT_SECONDS=15
DRIVE_LETTER="C:"
MIN_PD_VERSION="26.3.3"
OUTDATED_PK_EXPIRATION="2026-03-20"
PD_VERSION=""

function show_help() {
  echo "Parallels Windows VM BitLocker Suspend Script (All Users)"
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  -f, --format FORMAT   Output format: text (default), json, csv"
  echo "  -i, --vm-id ID        Target a specific VM ID or VM Name"
  echo "  -r, --run-non-running Start non-running VMs, suspend BitLocker, then suspend VMs again"
  echo "  -d, --drive LETTER    Target drive (default: C:)"
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
  -d | --drive)
    DRIVE_LETTER="$2"
    shift
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

function check_for_requirements() {
  if ! command -v "$PRLCTL_BIN" >/dev/null 2>&1; then
    if command -v prlctl >/dev/null 2>&1; then
      PRLCTL_BIN="$(command -v prlctl)"
    else
      echo "Error: prlctl is not installed"
      exit 1
    fi
  fi
}

function get_parallels_version() {
  local version_output
  local version_value

  version_output=$($PRLCTL_BIN --version 2>/dev/null || true)
  version_value=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

  if [ -z "$version_value" ]; then
    echo "Error: Unable to determine Parallels Desktop version from: $version_output"
    exit 1
  fi

  PD_VERSION="$version_value"
}

function version_gte() {
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

function enforce_parallels_version_gate() {
  if ! version_gte "$PD_VERSION" "$MIN_PD_VERSION"; then
    echo "Error: Parallels Desktop version $PD_VERSION is not supported. Minimum required version is $MIN_PD_VERSION."
    exit 1
  fi
}

function get_host_users() {
  dscl . list /Users | grep -v "^_" | grep '\S'
}

function wait_for_vm_running() {
  local owner="$1"
  local vm_id="$2"
  local remaining=30

  while [ "$remaining" -gt 0 ]; do
    current_state=$(sudo -u "$owner" "$PRLCTL_BIN" list "$vm_id" -a -i --json 2>/dev/null \
      | awk -F'"' '$2=="State"{print $4; exit}' 2>/dev/null || true)
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

function resume_if_paused() {
  local owner="$1"
  local vm_id="$2"

  local state
  state=$(sudo -u "$owner" "$PRLCTL_BIN" list "$vm_id" -a -i --json 2>/dev/null \
    | awk -F'"' '$2=="State"{print $4; exit}' 2>/dev/null || true)

  if [ "$state" = "paused" ]; then
    sudo -u "$owner" "$PRLCTL_BIN" resume "$vm_id" >/dev/null 2>&1 || true
    if ! wait_for_vm_running "$owner" "$vm_id"; then
      return 1
    fi
  fi

  return 0
}

function json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

function append_record() {
  local results_file="$1"
  local owner="$2"
  local vm_id="$3"
  local vm_name="$4"
  local vm_state="$5"
  local tools_state="$6"
  local action_status="$7"
  local message="$8"

  printf '{"owner":"%s","vmId":"%s","vmName":"%s","vmState":"%s","toolsState":"%s","actionStatus":"%s","message":"%s"}\n' \
    "$(json_escape "$owner")" \
    "$(json_escape "$vm_id")" \
    "$(json_escape "$vm_name")" \
    "$(json_escape "$vm_state")" \
    "$(json_escape "$tools_state")" \
    "$(json_escape "$action_status")" \
    "$(json_escape "$message")" >>"$results_file"
}

function get_vm_pk_expiration() {
  local owner="$1"
  local vm_id="$2"
  local output
  local expiry_line
  local pk_expiry

  local ps_command="try{\$b=(Get-SecureBootUEFI pk).Bytes;\$c=\$null;foreach(\$o in @(44,40)){try{\$c=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(,[byte[]]\$b[\$o..(\$b.Length-1)]);break}catch{}};if(\$c){\$pkExp=\$c.NotAfter.ToString('yyyy-MM-dd')}else{\$pkExp='Unknown'}}catch{\$pkExp='Unknown'};Write-Host ('PK Exp: '+\$pkExp)"

  output=$(sudo -u "$owner" "$PRLCTL_BIN" exec "$vm_id" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$ps_command" 2>&1 || true)
  expiry_line=$(echo "$output" | tr -d '\r' | grep -E '^PK Exp: ' | tail -n 1 || true)
  pk_expiry=$(echo "$expiry_line" | sed -E 's/^PK Exp:[[:space:]]*//')

  if [ -z "$pk_expiry" ]; then
    pk_expiry="Unknown"
  fi

  echo "$pk_expiry"
}

function suspend_bitlocker_for_one_reboot() {
  local results_file="$1"

  for owner in $(get_host_users); do
    [ -n "$owner" ] || continue
    [ -d "/Users/$owner" ] || continue

    log_verbose "Checking VMs for macOS user: $owner"
    vm_json=$(sudo -u "$owner" "$PRLCTL_BIN" list -a -i --json 2>/dev/null)
    if [ -z "$vm_json" ] || [ "$vm_json" = "[]" ]; then
      continue
    fi

    vm_lines=$(echo "$vm_json" | awk -F'"' -v vm_filter="$VM_FILTER" '
      /\{[[:space:]]*$/ {
        if (NF>=2 && $2=="GuestTools") in_gt=1
        depth++
        if (depth==1) { id=""; name=""; state=""; os=""; tools_state="unknown"; in_gt=0 }
        next
      }
      /^[[:space:]]*\},?[[:space:]]*$/ {
        if (in_gt && depth==2) in_gt=0
        if (depth==1 && os=="win-11" && (vm_filter=="" || name==vm_filter || id==vm_filter)) print id "\t" name "\t" state "\t" tools_state
        depth--; next
      }
      in_gt && $2=="state" { tools_state=$4; next }
      depth!=1             { next }
      $2=="ID"    { id=$4 }
      $2=="Name"  { name=$4 }
      $2=="State" { state=$4 }
      $2=="OS"    { os=$4 }
    ')
    if [ -z "$vm_lines" ]; then
      continue
    fi

    while IFS=$'\t' read -r vm_id vm_name vm_state tools_state; do
      [ -n "$vm_id" ] || continue

      log_verbose "Processing VM '$vm_name' ($vm_id) state=$vm_state tools=$tools_state"

      started_for_action="false"
      if [ "$vm_state" != "running" ]; then
        if [ "$FORCE_NON_RUNNING" != "true" ]; then
          append_record "$results_file" "$owner" "$vm_id" "$vm_name" "$vm_state" "$tools_state" "skipped" "VM is not running"
          continue
        fi

        log_verbose "Starting non-running VM '$vm_name' ($vm_id) from state $vm_state"
        start_or_resume_vm "$owner" "$vm_id" "$vm_state"
        if [ $? -ne 0 ]; then
          append_record "$results_file" "$owner" "$vm_id" "$vm_name" "$vm_state" "$tools_state" "error" "Failed to start or resume VM"
          continue
        fi

        log_verbose "Waiting $WAIT_SECONDS seconds for VM '$vm_name' ($vm_id) to settle"
        sleep "$WAIT_SECONDS"
        resume_if_paused "$owner" "$vm_id"
        if ! wait_for_vm_running "$owner" "$vm_id"; then
          append_record "$results_file" "$owner" "$vm_id" "$vm_name" "$vm_state" "$tools_state" "error" "VM did not reach running state"
          continue
        fi

        started_for_action="true"
      fi

      pk_expiry=$(get_vm_pk_expiration "$owner" "$vm_id")
      if [ "$pk_expiry" != "$OUTDATED_PK_EXPIRATION" ]; then
        append_record "$results_file" "$owner" "$vm_id" "$vm_name" "$vm_state" "$tools_state" "skipped" "PK is not outdated (PK Exp: $pk_expiry)"
        if [ "$started_for_action" = "true" ]; then
          log_verbose "Suspending VM '$vm_name' ($vm_id) after PK check"
          suspend_vm "$owner" "$vm_id"
        fi
        continue
      fi

      output=$(sudo -u "$owner" "$PRLCTL_BIN" exec "$vm_id" cmd /C "manage-bde -protectors -disable $DRIVE_LETTER -RebootCount 1" 2>&1)
      exit_code=$?

      if [ $exit_code -ne 0 ]; then
        error_msg=$(echo "$output" | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^ //;s/ $//')
        [ -n "$error_msg" ] || error_msg="Unable to suspend BitLocker protectors"
        append_record "$results_file" "$owner" "$vm_id" "$vm_name" "$vm_state" "$tools_state" "error" "$error_msg"
      else
        append_record "$results_file" "$owner" "$vm_id" "$vm_name" "$vm_state" "$tools_state" "ok" "BitLocker protectors suspended for one reboot"
      fi

      if [ "$started_for_action" = "true" ]; then
        log_verbose "Suspending VM '$vm_name' ($vm_id) after BitLocker operation"
        suspend_vm "$owner" "$vm_id"
      fi
    done <<<"$vm_lines"
  done
}

function print_output() {
  local results_file="$1"

  if [ "$FORMAT" = "json" ]; then
    awk -F'"' '
      BEGIN { total=0; ok=0; errors=0; skipped=0 }
      { total++; action=$24
        if (action=="ok") ok++
        else if (action=="error") errors++
        else if (action=="skipped") skipped++
        rec[total]=$0
      }
      END {
        printf "{\n  \"summary\": {\n    \"total\": %d,\n    \"ok\": %d,\n    \"errors\": %d,\n    \"skipped\": %d\n  },\n  \"records\": [\n", total, ok, errors, skipped
        for (i=1; i<=total; i++) {
          sep=(i<total) ? "," : ""
          printf "    %s%s\n", rec[i], sep
        }
        printf "  ]\n}\n"
      }
    ' "$results_file"
  elif [ "$FORMAT" = "csv" ]; then
    echo "owner,vmId,vmName,vmState,toolsState,actionStatus,message"
    awk -F'"' '{ printf "\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"\n", $4,$8,$12,$16,$20,$24,$28 }' "$results_file"
  elif [ "$FORMAT" = "text" ]; then
    awk -F'"' '
      BEGIN { total=0; ok=0; errors=0; skipped=0 }
      { action=$24; vm_name=$12; vm_id=$8; msg=$28; total++
        if (action=="ok")      { print "OK: " vm_name " (" vm_id ")"; ok++ }
        else if (action=="skipped") { print "SKIPPED: " vm_name " (" vm_id ") - " msg; skipped++ }
        else                   { print "ERROR: " vm_name " (" vm_id ") - " msg; errors++ }
      }
      END {
        if (total==0) print "No Windows VMs found"
        else printf "Summary: total=%d, ok=%d, errors=%d, skipped=%d\n", total, ok, errors, skipped
      }
    ' "$results_file"
  else
    echo "Error: Unsupported format '$FORMAT'. Use text, json, or csv." >&2
    return 1
  fi
}

check_for_requirements
get_parallels_version
enforce_parallels_version_gate

results_file=$(mktemp /tmp/bitlocker-suspend-records.XXXXXX)

suspend_bitlocker_for_one_reboot "$results_file"

if [ ! -s "$results_file" ]; then
  if [ "$FORMAT" = "json" ]; then
    echo '{"summary":{"total":0,"ok":0,"errors":0,"skipped":0},"records":[]}'
  elif [ "$FORMAT" = "csv" ]; then
    echo "owner,vmId,vmName,vmState,toolsState,actionStatus,message"
  else
    echo "No Windows VMs found"
  fi
  rm -f "$results_file"
  exit 0
fi

print_output "$results_file"
rm -f "$results_file"
exit 0