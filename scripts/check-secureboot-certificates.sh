#!/bin/bash

set -euo pipefail

VM_FILTER=""
SILENT="false"
WAIT_SECONDS=15
VERBOSE="false"

usage() {
  cat <<'EOF'
Usage:
  ./check-secureboot-certificates.sh [--vm "VM Name or UUID"] [--silent] [--verbose]

Description:
  Executes this PowerShell expression in running Windows VMs:
    Get-SecureBootUEFI -Name PK -Decoded; Get-SecureBootUEFI -Name KEK -Decoded

Output per VM:
  - PK Exp: <date>, KEK Exp: <date>

Optional behavior:
  --silent
    Only check already-running Windows VMs; do not start or resume non-running VMs.

  --verbose
    Print extra diagnostics when status cannot be determined.
EOF
}

wait_for_vm_running() {
  local vm_id="$1"
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
  local vm_id="$1"
  local vm_state="$2"

  if [[ "$vm_state" == "paused" || "$vm_state" == "suspended" ]]; then
    "${PRLCTL_EXEC[@]}" resume "$vm_id" </dev/null >/dev/null 2>&1
  else
    "${PRLCTL_EXEC[@]}" start "$vm_id" </dev/null >/dev/null 2>&1
  fi
}

resume_if_paused() {
  local vm_id="$1"

  local state
  state=$("${PRLCTL_EXEC[@]}" list "$vm_id" -a -i --json 2>/dev/null \
    | awk -F'"' '$2=="State"{print $4; exit}' 2>/dev/null || true)

  if [[ "$state" == "paused" ]]; then
    "${PRLCTL_EXEC[@]}" resume "$vm_id" </dev/null >/dev/null 2>&1 || true
    if ! wait_for_vm_running "$vm_id"; then
      return 1
    fi
  fi

  return 0
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

if ! command -v prlctl >/dev/null 2>&1; then
  echo "prlctl is not installed"
  exit 1
fi

HOST_USER=$(stat -f%Su /dev/console)

# When running as root (e.g. via MDM), sudo to the console user.
# When already running as the console user, invoke prlctl directly.
if [[ "$(id -u)" == "0" ]]; then
  PRLCTL_EXEC=(sudo -u "$HOST_USER" prlctl)
else
  PRLCTL_EXEC=(prlctl)
fi

# Tab-separated: id<TAB>name<TAB>state — one line per matching Windows VM
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
  VM_COUNT=$(echo "$VMS_DATA" | wc -l | tr -d ' ')
else
  VM_COUNT=0
fi
if [[ "$VM_COUNT" -eq 0 ]]; then
  if [[ "$SILENT" != "true" ]]; then
    echo "No Windows VMs found"
  else
    echo "No running Windows VMs found"
  fi
  exit 0
fi

# Walk all concatenated EFI_SIGNATURE_LIST entries and return the latest (furthest-future) cert expiry.
# EFI_SIGNATURE_LIST header: 16 (type GUID) + 4 (list size) + 4 (header size) + 4 (sig size) = 28 bytes,
# then EFI_SIGNATURE_DATA entries: 16 bytes SignatureOwner GUID + DER cert bytes.
# Falls back to probing offsets 40/44 from each list start for Parallels variants that omit the SignatureSize field.
# Uses bash double-quotes so PS variables are escaped with \$ to survive shell expansion.
PS_COMMAND="function g([byte[]]\$b){\$r=\$null;\$p=0;while((\$p+28) -le \$b.Length){\$lsz=[BitConverter]::ToInt32(\$b,\$p+16);if(\$lsz -le 0 -or (\$p+\$lsz) -gt \$b.Length){break};\$hsz=[BitConverter]::ToInt32(\$b,\$p+20);\$ssz=[BitConverter]::ToInt32(\$b,\$p+24);\$ds=\$p+28+\$hsz;\$de=\$p+\$lsz;if(\$ssz -ge 17 -and (\$ds+\$ssz) -le \$de){while((\$ds+\$ssz) -le \$de){try{\$c=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(,[byte[]]\$b[(\$ds+16)..(\$ds+\$ssz-1)]);if(!\$r -or \$c.NotAfter -gt \$r){\$r=\$c.NotAfter}}catch{};\$ds+=\$ssz}}else{foreach(\$o in @(40,44)){try{\$c=New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(,[byte[]]\$b[(\$p+\$o)..(\$b.Length-1)]);if(!\$r -or \$c.NotAfter -gt \$r){\$r=\$c.NotAfter};break}catch{}}};\$p+=\$lsz};if(\$r){\$r.ToString('yyyy-MM-dd')}else{'Unknown'}};try{\$pkExp=g((Get-SecureBootUEFI pk).Bytes)}catch{\$pkExp='Unknown'};try{\$kekExp=g((Get-SecureBootUEFI kek).Bytes)}catch{\$kekExp='Unknown'};Write-Host('PK Exp: '+\$pkExp+', KEK Exp: '+\$kekExp)"

# Convert tabs to newlines to iterate safely without IFS issues in bash 3.2
while IFS= read -r vm_line || [[ -n "$vm_line" ]]; do
  vm_id=$(echo "$vm_line" | cut -f1)
  vm_name=$(echo "$vm_line" | cut -f2)
  vm_state=$(echo "$vm_line" | cut -f3)
  # Process VM

  started_for_check="false"
  if [[ "$vm_state" != "running" ]]; then
    if [[ "$SILENT" == "true" ]]; then
      echo "$vm_name: PK/KEK expiration not available (VM not running)"
      continue
    fi

    start_or_resume_vm "$vm_id" "$vm_state"
    if ! wait_for_vm_running "$vm_id"; then
      echo "$vm_name: Unable to determine SecureBoot certificate status"
      continue
    fi

    sleep "$WAIT_SECONDS"
    if ! resume_if_paused "$vm_id"; then
      echo "$vm_name: Unable to determine SecureBoot certificate status"
      continue
    fi
    started_for_check="true"
  fi

  output=$("${PRLCTL_EXEC[@]}" exec "$vm_id" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$PS_COMMAND" </dev/null 2>&1 || true)
  expiry_line=$(echo "$output" | tr -d '\r' | grep -E '^PK Exp: ' | tail -n 1 || true)

  if [[ -n "$expiry_line" ]]; then
    echo "$vm_name: $expiry_line"
  else
    echo "$vm_name: Unable to determine PK/KEK expiration"
    if [[ "$VERBOSE" == "true" ]]; then
      echo "$vm_name: raw output:"
      echo "$output"
    fi
  fi

  if [[ "$started_for_check" == "true" ]]; then
    "${PRLCTL_EXEC[@]}" suspend "$vm_id" </dev/null >/dev/null 2>&1 || true
  fi
done <<< "$VMS_DATA"

