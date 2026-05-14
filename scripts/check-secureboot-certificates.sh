#!/bin/bash

set -euo pipefail

VM_FILTER=""
RUN_NON_RUNNING="false"
WAIT_SECONDS=60
VERBOSE="false"

usage() {
  cat <<'EOF'
Usage:
  ./check-secureboot-certificates.sh [--vm "VM Name or UUID"] [--run-non-running] [--verbose]

Description:
  Executes this PowerShell expression in running Windows VMs:
    ([System.Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI db).bytes) -match "Windows UEFI CA 2023")

Output per VM:
  - False => X SecureBoot certificates require update
  - True  => V SecureBoot certificates are up to date

Optional behavior:
  --run-non-running
    Start or resume non-running Windows VMs, wait 60 seconds, check status,
    then suspend only VMs started/resumed by this script.

  --verbose
    Print extra diagnostics when status cannot be determined.
EOF
}

wait_for_vm_running() {
  local vm_id="$1"
  local remaining=30

  while [[ "$remaining" -gt 0 ]]; do
    state=$(sudo -u "$HOST_USER" prlctl list "$vm_id" -a -i --json 2>/dev/null | jq -r '.[0].State // empty')
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
    sudo -u "$HOST_USER" prlctl resume "$vm_id" >/dev/null 2>&1
  else
    sudo -u "$HOST_USER" prlctl start "$vm_id" >/dev/null 2>&1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vm)
      VM_FILTER="$2"
      shift 2
      ;;
    --run-non-running)
      RUN_NON_RUNNING="true"
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

if ! command -v prlctl >/dev/null 2>&1; then
  echo "prlctl is not installed"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is not installed. Install it with: brew install jq"
  exit 1
fi

HOST_USER=$(stat -f%Su /dev/console)

if [[ -n "$VM_FILTER" ]]; then
  NAME_FILTER=" and (.Name == \"$VM_FILTER\" or .ID == \"$VM_FILTER\")"
else
  NAME_FILTER=""
fi

if [[ "$RUN_NON_RUNNING" == "true" ]]; then
  VMS_JSON=$(sudo -u "$HOST_USER" prlctl list -a -i --json | jq -r "map(select((.OS == \"win-10\" or .OS == \"win-11\")${NAME_FILTER}) | {id:.ID, name:.Name, state:.State})")
else
  VMS_JSON=$(sudo -u "$HOST_USER" prlctl list -a -i --json | jq -r "map(select((.OS == \"win-10\" or .OS == \"win-11\") and .State == \"running\"${NAME_FILTER}) | {id:.ID, name:.Name, state:.State})")
fi

VM_COUNT=$(echo "$VMS_JSON" | jq 'length')
if [[ "$VM_COUNT" -eq 0 ]]; then
  if [[ "$RUN_NON_RUNNING" == "true" ]]; then
    echo "No Windows VMs found"
  else
    echo "No running Windows VMs found"
  fi
  exit 0
fi

PS_COMMAND="([System.Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI db).bytes) -match 'Windows UEFI CA 2023')"

while IFS= read -r -u 3 vm; do
  vm_id=$(echo "$vm" | jq -r '.id')
  vm_name=$(echo "$vm" | jq -r '.name')
  vm_state=$(echo "$vm" | jq -r '.state')

  started_for_check="false"
  if [[ "$vm_state" != "running" ]]; then
    if [[ "$RUN_NON_RUNNING" != "true" ]]; then
      continue
    fi

    start_or_resume_vm "$vm_id" "$vm_state"
    if ! wait_for_vm_running "$vm_id"; then
      echo "$vm_name: Unable to determine SecureBoot certificate status"
      continue
    fi

    sleep "$WAIT_SECONDS"
    started_for_check="true"
  fi

  output=$(sudo -u "$HOST_USER" prlctl exec "$vm_id" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$PS_COMMAND" 2>&1 || true)
  result=$(echo "$output" | tr -d '\r' | grep -Eo 'True|False' | tail -n 1 || true)

  case "$result" in
    True)
      echo "$vm_name: V SecureBoot certificates are up to date"
      ;;
    False)
      echo "$vm_name: X SecureBoot certificates require update"
      ;;
    *)
      echo "$vm_name: Unable to determine SecureBoot certificate status"
      if [[ "$VERBOSE" == "true" ]]; then
        echo "$vm_name: raw output:"
        echo "$output"
      fi
      ;;
  esac

  if [[ "$started_for_check" == "true" ]]; then
    sudo -u "$HOST_USER" prlctl suspend "$vm_id" >/dev/null 2>&1 || true
  fi
done 3< <(echo "$VMS_JSON" | jq -c '.[]')
