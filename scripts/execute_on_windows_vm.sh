#! /bin/bash

# This script is used to execute a command on a Windows VM.
# It will execute the command in cmd or pwsh mode, depending on the mode argument.
# It will also output the command output to the console.
# It will also return the exit code of the command.
#
# Requirements:
# - prlctl
# - jq
# - osascript
#
# Usage:
# ./execute_on_windows_vm.sh --mode cmd --name "VM Name" --command "echo test"

MODE="cmd"
VM_ID=""
VERBOSE="false"
COMMAND=""

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

function get_vm_by_name_or_id() {
  local ID=$1
  local NAME_FILTER=$2

  if [ -z "$ID" ]; then
    NAME_FILTER=""
  else
    NAME_FILTER="and (.Name == \"$1\" or .ID == \"$1\")"
  fi

  sudo -u "$USER" prlctl list -a -i --json | /tmp/jq -r "map(select((.OS == \"win-10\" or .OS == \"win-11\") $NAME_FILTER and .State == \"running\") | {id:.ID, name: .Name, tools_state: .GuestTools.state, state: .State})"
}

function execute_on_windows_vm() {
  local TARGET_VM_ID=$1
  local MODE=$2
  local COMMAND=$3
  IDS=$(get_vm_by_name_or_id "$TARGET_VM_ID")

  if [ ${#VM_ARRAY[@]} -eq 0 ]; then
    VM_ARRAY=()
    while IFS= read -r line; do
      VM_ARRAY+=("$line")
    done < <(echo "$IDS" | /tmp/jq -c '.[]')
  fi

  if [ "$VERBOSE" = "true" ]; then
    echo "Found ${#VM_ARRAY[@]} VM(s) running windows, checking for updates"
  fi

  if [ ${#VM_ARRAY[@]} -eq 0 ]; then
    echo "No running Windows VMs found"
    exit 0
  fi

  ERROR_ARRAY=()
  for VM in "${VM_ARRAY[@]}"; do
    ID=$(echo "$VM" | /tmp/jq -r '.id')
    vm_name=$(echo "$VM" | /tmp/jq -r '.name')
    vm_state=$(echo "$VM" | /tmp/jq -r '.state')
    tools_state=$(echo "$VM" | /tmp/jq -r '.tools_state')
    if [ -z "$ID" ] || [ "$ID" = "null" ]; then
      echo "VM $TARGET_VM_ID not found or not running"
      ERROR_ARRAY+=("$vm_name ($ID) not found or not running")
    fi

    if [ "$VERBOSE" = "true" ]; then
      if [ ${#VM_ARRAY[@]} -gt 1 ]; then
        echo "Executing command on VM: $vm_name ($ID)"
      fi
    fi

    if [ "$MODE" = "cmd" ]; then
      if [ "$VERBOSE" = "true" ]; then
        echo "Executing command in cmd"
      fi
      CMD="cmd /C"
    elif [ "$MODE" = "pwsh" ]; then
      if [ "$VERBOSE" = "true" ]; then
        echo "Executing command in pwsh"
      fi
      CMD="pwsh -Command"
    else
      CMD=""
    fi

    # Trim leading and trailing spaces from the command
    COMMAND=$(echo "$COMMAND" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [ -z "$COMMAND" ]; then
      echo "Error: No command specified"
      exit 1
    fi

    if [ "$VERBOSE" = "true" ]; then
      echo "Executing command '$COMMAND' in $MODE mode on VM $ID"
    fi
    OUTPUT=$(sudo -u "$USER" prlctl exec "$ID" $CMD $COMMAND)
    last_exit_code=$?
    if [ $last_exit_code -ne 0 ]; then
      ERROR_ARRAY+=("$vm_name ($ID) failed with exit code $last_exit_code")
    fi
    if [ "$VERBOSE" = "true" ] && [ ${#VM_ARRAY[@]} -eq 1 ]; then
      echo "Command output:"
    fi
    if [ ${#VM_ARRAY[@]} -gt 1 ]; then
      echo "Command output for $vm_name ($ID):"
    fi
    echo "$OUTPUT"
  done
  if [ ${#ERROR_ARRAY[@]} -gt 0 ]; then
    echo "Errors:"
    for error in "${ERROR_ARRAY[@]}"; do
      echo "$error"
    done
    exit 1
  fi
}

function show_help() {
  local mode=$1

  if [ -z "$mode" ]; then
    echo "Parallels Desktop Windows VM Command Execution Script"
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Description:"
    echo "  Executes commands on Windows VMs using either cmd or PowerShell."
    echo
    echo "Options:"
    echo "  -m, --mode MODE       Execution mode (cmd or pwsh)"
    echo "  -n, --name NAME       Target VM by name"
    echo "  -i, --id ID          Target VM by ID"
    echo "  -v, --verbose        Enable verbose output"
    echo "  -h, --help           Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --mode cmd --name \"Windows VM\" --command \"echo test\""
    echo "  $0 --mode pwsh --id \"123456\" --command \"Get-Process\""
    echo
  fi

  if [ -n "$mode" ]; then
    echo "Parallels Desktop Windows VM Command Execution Script - $mode Mode"
    echo
    case "$mode" in
    "cmd")
      echo "Usage: $0 --mode cmd [OPTIONS] --command \"COMMAND\""
      echo
      echo "Description:"
      echo "  Executes commands using Windows Command Prompt (cmd.exe)."
      echo
      echo "Options:"
      echo "  -n, --name NAME    Target VM by name"
      echo "  -i, --id ID       Target VM by ID"
      echo "  -v, --verbose     Show detailed execution information"
      echo "  -h, --help        Show this help message"
      echo
      echo "Example:"
      echo "  $0 --mode cmd --name \"Windows VM\" --command \"dir C:\\\""
      ;;
    "pwsh")
      echo "Usage: $0 --mode pwsh [OPTIONS] --command \"COMMAND\""
      echo
      echo "Description:"
      echo "  Executes commands using Windows PowerShell."
      echo
      echo "Options:"
      echo "  -n, --name NAME    Target VM by name"
      echo "  -i, --id ID       Target VM by ID"
      echo "  -v, --verbose     Show detailed execution information"
      echo "  -h, --help        Show this help message"
      echo
      echo "Example:"
      echo "  $0 --mode pwsh --name \"Windows VM\" --command \"Get-Process\""
      ;;
    esac
    echo
  fi
}

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
  -h | --help)
    show_help "$MODE"
    exit 0
    ;;
  -v | --verbose)
    VERBOSE="true"
    shift
    ;;
  -m | --mode)
    MODE="$2"
    shift
    shift
    ;;
  -n | --name)
    VM_ID="$2"
    shift
    shift
    ;;
  -i | --id)
    VM_ID="$2"
    shift
    shift
    ;;
  *)
    COMMAND="$COMMAND $1"
    shift
    ;;
  esac
done

if [ -z "$MODE" ]; then
  echo "Error: No mode specified"
  show_help
  exit 1
fi

if [ -z "$COMMAND" ]; then
  echo "Error: No command specified"
  show_help "$MODE"
  exit 1
fi

USER=$(stat -f%Su /dev/console)

if [ "$VERBOSE" = "true" ]; then
  echo "Using logged in user: $USER"
fi

check_for_requirements

if [ -z "$VM_ID" ]; then
  VM_ID=$VM_NAME
fi

execute_on_windows_vm "$VM_ID" "$MODE" "$COMMAND"

#get_vm_by_name_or_id "$VM_ID"
