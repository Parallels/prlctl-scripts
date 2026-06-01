#!/bin/bash

############
# Report SecureBoot PK certificate status for Windows 11 Parallels VMs.
#
# Reads the PK certificate hash from VmInfo.pvi (written by Parallels Tools >= 26.3.3)
# and prints a summary without starting or modifying any VMs.
#
# Requirements:
# - Parallels Desktop >= 26.3.3
#
# Usage examples:
# ./get-secureboot-pk-status.sh
# ./get-secureboot-pk-status.sh --vm "Windows 11"
# ./get-secureboot-pk-status.sh --verbose
############

set -u

PRLCTL_BIN="/usr/local/bin/prlctl"
MIN_PD_VERSION="26.3.3"
OUTDATED_PK_HASH="7ec69a1bd679fb7aa7b22ce6b3d0204113b19591db1f1d52014022d8c74f0d53"
VM_FILTER=""
VERBOSE="false"
PD_VERSION=""

usage() {
  cat <<'EOF'
Usage:
  ./get-secureboot-pk-status.sh [--vm "VM Name or UUID"] [--verbose]

Description:
  Reads the PK certificate hash from VmInfo.pvi for each Windows 11 VM
  belonging to the console user and prints a status summary.
  No VMs are started or modified.

Output:
  All VMs have updated certificates
  One or more VMs have outdated certificates
  Waiting for Parallels Tools to be updated on one or more VMs
  (Multiple lines printed if different states coexist)

Exit codes:
  0 = Script completed
  1 = Fatal prerequisite failure
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vm)
      VM_FILTER="$2"
      shift 2
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
    echo "Parallels Desktop must be updated to $MIN_PD_VERSION (current: $PD_VERSION)"
    exit 1
  fi
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

# ─── Main ─────────────────────────────────────────────────────────────────────

check_for_requirements
get_parallels_version
enforce_parallels_version_gate

HOST_USER=$(stat -f%Su /dev/console)
if [[ -z "$HOST_USER" || "$HOST_USER" == "root" || "$HOST_USER" == "loginwindow" ]]; then
  echo "No console user logged in"
  exit 0
fi

# When running as root (e.g. via MDM), sudo to the console user.
# When already running as the console user, invoke prlctl directly.
if [[ "$(id -u)" == "0" ]]; then
  PRLCTL_EXEC=(sudo -u "$HOST_USER" "$PRLCTL_BIN")
else
  PRLCTL_EXEC=("$PRLCTL_BIN")
fi

log_verbose "Console user: $HOST_USER"
log_verbose "Parallels Desktop version: $PD_VERSION"

VMS_DATA=$("${PRLCTL_EXEC[@]}" list -a -i --json 2>/dev/null \
  | awk -F'"' -v vm_filter="$VM_FILTER" '
    /\{[[:space:]]*$/  { depth++; if (depth==1) { id=""; name=""; os=""; home="" }; next }
    /^[[:space:]]*\},?[[:space:]]*$/ {
      if (depth==1 && os=="win-11" && (vm_filter=="" || name==vm_filter || id==vm_filter)) { gsub(/\\/, "", home); print id "\t" name "\t" home }
      depth--; next
    }
    depth!=1  { next }
    $2=="ID"    { id=$4 }
    $2=="Name"  { name=$4 }
    $2=="OS"    { os=$4 }
    $2=="Home"  { home=$4 }
' || true)

if [[ -z "$VMS_DATA" ]]; then
  echo "No Windows 11 VMs found"
  exit 0
fi

COUNT_OUTDATED=0
COUNT_MISSING=0
COUNT_OK=0

while IFS=$'\t' read -r vm_id vm_name vm_home || [[ -n "$vm_id" ]]; do
  [[ -n "$vm_id" ]] || continue

  pk_hash=$(get_pk_hash "$vm_home")

  if [[ -z "$pk_hash" ]]; then
    COUNT_MISSING=$((COUNT_MISSING + 1))
    log_verbose "$vm_name: Parallels Tools not updated yet (no PK hash in VmInfo.pvi)"
  elif [[ "$pk_hash" == "$OUTDATED_PK_HASH" ]]; then
    COUNT_OUTDATED=$((COUNT_OUTDATED + 1))
    log_verbose "$vm_name: Certificates are outdated (PK hash: $pk_hash)"
  else
    COUNT_OK=$((COUNT_OK + 1))
    log_verbose "$vm_name: Certificates are up to date (PK hash: $pk_hash)"
  fi
done <<< "$VMS_DATA"

# ── Summary ───────────────────────────────────────────────────────────────────

if [[ "$COUNT_OUTDATED" -gt 0 ]]; then
  echo "One or more VMs have outdated certificates"
fi

if [[ "$COUNT_MISSING" -gt 0 ]]; then
  echo "Waiting for Parallels Tools to be updated on one or more VMs"
fi

if [[ "$COUNT_OUTDATED" -eq 0 && "$COUNT_MISSING" -eq 0 ]]; then
  echo "All VMs have updated certificates"
fi

exit 0
