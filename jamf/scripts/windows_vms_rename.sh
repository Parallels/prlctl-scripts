#!/bin/bash
#
# windows_vms_rename.sh   (v0.8.0)
#
# Sets the Windows computer name inside Parallels Desktop VMs to a name built
# from the Mac serial number (default: VM + serial). When the user has several
# Windows VMs, the first keeps that name and the others get 2, 3, ... added.
# Proof-of-concept script, provided as is. Uses only Parallels Desktop's command
# line (prlctl) and Parallels Tools; it does not change the product. Test it on
# a few Macs before wider use.
#
# Requires Parallels Desktop Pro or Business: prlctl start/exec/status are
# refused on Standard edition, and the script exits 1 with a clear log line.
#
# Jamf script parameters ($1-$3 are reserved by Jamf):
#   $4  NAME_PATTERN  text containing {serial}; optional {n}
#                     marks where the VM number goes          default: VM{serial}
#   $5  REBOOT        now | defer                             default: now
#   $6  COUNTDOWN     seconds from the notice to the restart
#                     of a running VM, 0-3600                 default: 300
#   $7  DRY_RUN       true | false                            default: false
#   $8  VM_FILTER     extended regex on VM name               default: (none)
# Nothing is read from the environment: the script runs as root.
#
# Several VMs: the name comes from the Mac serial, so two VMs would otherwise
# get the same name and clash on the network and in directory and asset tools.
# Every matching Windows VM of the logged-in user is renamed, and each gets a
# number: VM 1 gets the plain name (VMC02XYZ123ABC), VMs 2, 3, ... add their
# number at the end (VMC02XYZ123ABC2), or at {n} when NAME_PATTERN has it. A
# single VM always gets the plain name. A VM keeps the number an earlier run
# gave it, so adding or deleting a VM does not rename (and restart) the others;
# a new VM gets the lowest free number. Numbers are kept per VM in the state
# file and are counted among the logged-in user's VMs only, in VM name order.
#
# Windows allows at most 15 characters. Mac serials have 10 characters (2021
# and later) or 12 (older Macs), so with a 12-character serial VM{serial} is 14
# characters and leaves room for VMs 2 to 9. A VM whose numbered name would be
# longer than 15 characters fails, and the others are still renamed.
#
# The VM is renamed when the script runs, once Windows and Parallels Tools are
# up, so a VM created since the last run is picked up by the next run. Naming a
# VM while it is being created is not covered.
#
# What happens depends on the VM's power state when the script fires:
#   stopped    notice -> start -> rename -> restart -> verify -> shut down again.
#   running    rename -> notice with a countdown (COUNTDOWN) -> restart ->
#              verify -> leave it running. REBOOT=defer stages the name instead.
#   paused / suspended  notice -> resume -> rename -> put back, with no restart,
#              so the frozen Windows session keeps its unsaved work. The name
#              applies at the next Windows restart ("pending-restart"); if the VM
#              is running at a later run and REBOOT=now, that run restarts it
#              like any running VM.
#   other states (starting, stopping, ...)  skipped; the next run retries.
# A VM that already has the right name is left alone, with no notice. A stopped,
# paused or suspended VM that an earlier run already handled is not woken again.
#
# A VM that failed is not retried for RETRY_AFTER seconds (24 hours), so a
# recurring policy does not start it and notify the user at every check-in.
# A VM joined to an Active Directory domain is not renamed: that needs domain
# credentials, which this script does not hold. Rename it through the domain.
# To retry such a VM sooner, delete its line from the state file (vms.tsv).
#
# Safe to run repeatedly. DRY_RUN=true starts nothing and writes no state.
# Log: /Library/Logs/ParallelsVMRename.log (also the Jamf script result).
#
# Local test (as root); parameters 1-3 are placeholders:
#   sudo ./windows_vms_rename.sh x x x 'VM{serial}' now 300 true
#
# Exit code: 0 = done or nothing to do, 1 = a VM failed, the VM list could not
# be read or the Parallels Desktop edition is not supported, 2 = invalid
# parameter.

set -u
umask 022
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"

NAME_PATTERN="${4:-}"
[ -n "$NAME_PATTERN" ] || NAME_PATTERN='VM{serial}'
REBOOT="${5:-now}"
COUNTDOWN="${6:-300}"
DRY_RUN="${7:-false}"
VM_FILTER="${8:-}"

NL=$'\n'
READY_TIMEOUT=240      # seconds to wait for Windows + Parallels Tools, also after a restart
RETRY_AFTER=86400      # seconds before a VM that failed is tried again
LOCK_MAX_AGE=7200      # seconds after which a run lock counts as stale even if its pid is alive
NOTIFY_TIMEOUT=60      # seconds before a jamfHelper window without a countdown closes itself
JAMFHELPER="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
PD_ICON="/Applications/Parallels Desktop.app/Contents/Resources/Parallels.icns"

# Root-owned locations. The lock lives in STATE_DIR, not in world-writable /var/tmp.
LOG_FILE="/Library/Logs/ParallelsVMRename.log"
STATE_DIR="/Library/Application Support/ParallelsVMRename"
STATE_FILE="$STATE_DIR/vms.tsv"            # id, name, status, updated, number
LOCK_DIR="$STATE_DIR/run.lock"

CONSOLE_USER=""
PRLCTL=""
BRING_UP_ERR=""

# ---------------------------------------------------------------- helpers ---

log() {
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') [$$] $*"
  echo "$line"
  echo "$line" >>"$LOG_FILE" 2>/dev/null
}

lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Tell the console user what is about to happen. Never blocks the run.
notify_user() { # heading message [countdown-seconds]
  local timeout="$NOTIFY_TIMEOUT" args
  if [ ! -x "$JAMFHELPER" ]; then
    log "NOTIFY skipped, jamfHelper not installed: '$1'"
    return 0
  fi
  log "NOTIFY '$1': ${2//$'\n'/ }"
  args=(-windowType utility -title "Windows VM update" -heading "$1" -description "$2"
    -alignHeading left -alignDescription left -button1 "OK" -defaultButton 1)
  [ -f "$PD_ICON" ] && args+=(-icon "$PD_ICON" -iconSize 96)
  # A countdown ties the window to the restart: it counts down and closes when the VM restarts.
  if [ "${3:-0}" -gt 0 ] 2>/dev/null; then
    timeout="$3"
    args+=(-countdown -countdownPrompt "The VM restarts in " -alignCountdown left)
  fi
  "$JAMFHELPER" "${args[@]}" -timeout "$timeout" >/dev/null 2>&1 &
}

# Run prlctl as the console user (VMs belong to the user, not root). Input is
# /dev/null so that 'prlctl exec' cannot read the VM list the main loop reads.
prl() { sudo -u "$CONSOLE_USER" "$PRLCTL" "$@" </dev/null; }

# Run a command inside a VM through Parallels Tools; strip Windows CRs.
vm_exec() {
  local ref="$1"
  shift
  prl exec "$ref" "$@" 2>/dev/null | tr -d '\r'
}

ps_exec() { # ref command   (PowerShell inside the VM)
  vm_exec "$1" powershell.exe -NoProfile -NonInteractive -Command "$2"
}

# 'prlctl status' is refused on Standard edition; 'list -o status' works everywhere.
vm_state() { prl list -a "$1" -o status --no-header 2>/dev/null | awk '{print $1; exit}'; }

# prlctl start/exec/status are refused on Standard edition ("available only in ...
# Pro or Business Edition"). Say so up front instead of timing out per VM.
check_edition() {
  local srv="${PRLCTL%prlctl}prlsrvctl" edition
  [ -x "$srv" ] || return 0
  edition="$(sudo -u "$CONSOLE_USER" "$srv" info --license 2>/dev/null </dev/null |
    awk -F'"' '/edition=/ {print tolower($2); exit}')"
  [ "$edition" != "standard" ] && return 0
  log "Parallels Desktop edition is 'standard': prlctl start/exec need Pro or Business, so no VM can be renamed on this Mac"
  return 1
}

get_serial() {
  ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null |
    awk -F'"' '/IOPlatformSerialNumber/ {print $4; exit}'
}

# render_name <pattern> <serial> [n]: replaces {serial}. VM number 1 (the
# default) gets the plain name; 2 and up add the number, at {n} when the pattern
# has it, else at the end. The caller checks the result with valid_name.
render_name() {
  local s suffix=""
  case "$1" in *'{serial}'*) ;; *) return 1 ;; esac
  [ "${3:-1}" -gt 1 ] 2>/dev/null && suffix="$3"
  s="${1//\{serial\}/$2}"
  if [ -z "$suffix" ]; then # plain name: a hyphen next to {n} goes with it
    s="${s//-\{n\}/}"
    s="${s//\{n\}-/}"
  fi
  case "$s" in
    *'{n}'*) printf '%s' "${s//\{n\}/$suffix}" ;;
    *) printf '%s%s' "$s" "$suffix" ;;
  esac
}

# A valid Windows computer name: 1-15 letters, digits or hyphens, no hyphen at
# either end, not all digits. It also goes into a PowerShell command line, so
# nothing else may get through.
valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,13}[A-Za-z0-9])?$ ]] || return 1
  case "$1" in *[!0-9]*) return 0 ;; esac
  return 1
}

# Take the run lock. A lock left by a killed run (Jamf timeout, crash) is stale
# when its pid is gone or it is older than LOCK_MAX_AGE, and is replaced instead
# of blocking every later run.
acquire_lock() {
  local pid age
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ >"$LOCK_DIR/pid"
    return 0
  fi
  pid="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
  age=$(($(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)))
  # Another run that has just created the lock may not have written its pid yet.
  [ -z "$pid" ] && [ "$age" -lt 10 ] && return 1
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ "$age" -lt "$LOCK_MAX_AGE" ]; then
    return 1
  fi
  log "Removing stale lock (pid='${pid:-none}', age ${age}s)"
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null || return 1
  echo $$ >"$LOCK_DIR/pid"
}

# ------------------------------------------------------------------ state ---

state_get() { # id -> "name<TAB>status<TAB>updated<TAB>number", or nothing
  [ -f "$STATE_FILE" ] || return 0
  awk -F'\t' -v id="$1" '$1 == id {print $2 "\t" $3 "\t" $4 "\t" $5; exit}' "$STATE_FILE"
}

state_put() { # id name number status   (number is empty when NAME_PATTERN has no {n})
  [ "$DRY_RUN" = "true" ] && return 0
  local tmp
  # Next to the state file, so that 'mv' replaces it in one step.
  if ! tmp="$(mktemp "$STATE_DIR/.vms.XXXXXX" 2>/dev/null)"; then
    log "WARN   could not write the state file in $STATE_DIR"
    return 0
  fi
  [ -f "$STATE_FILE" ] && awk -F'\t' -v id="$1" '$1 != id' "$STATE_FILE" >"$tmp"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$4" "$(date +%s)" "$3" >>"$tmp"
  mv "$tmp" "$STATE_FILE"
  chmod 644 "$STATE_FILE"
}

# ---------------------------------------------------------- VM inventory ---

# Reads 'prlctl list -a -i --json' on stdin and prints one line per Windows VM:
# id<TAB>name<TAB>state<TAB>toolsState. Fails when the input is not valid JSON.
windows_vms_from_json() {
  osascript -l JavaScript -e '
    function run() {
      var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
      var text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
      var vms = JSON.parse(text);
      var out = [];
      vms.forEach(function (vm) {
        if (!/^win/.test(vm.OS || "")) return;
        var tools = (vm.GuestTools && vm.GuestTools.state) ? vm.GuestTools.state : "unknown";
        var clean = function (s) { return String(s || "").replace(/[\t\r\n]/g, " "); };
        out.push([clean(vm.ID), clean(vm.Name) || "(no name)", clean(vm.State), clean(tools)].join("\t"));
      });
      return out.join("\n");
    }' 2>/dev/null
}

# Start or resume the VM. On failure sets BRING_UP_ERR to prlctl's message.
bring_up() { # ref state
  local verb out rc
  BRING_UP_ERR=""
  case "$2" in
    running) return 0 ;;
    paused | suspended) verb=resume ;;
    stopped) verb=start ;;
  esac
  out="$(prl "$verb" "$1" 2>&1)"
  rc=$?
  [ "$rc" -eq 0 ] && return 0
  BRING_UP_ERR="prlctl exit $rc: $(printf '%s' "$out" | tr '\n\r' '  ' | head -c 300)"
  return 1
}

restore_state() { # ref originalState
  local verb out
  case "$2" in
    stopped) verb=stop ;;
    suspended) verb=suspend ;;
    paused) verb=pause ;;
    *) return 0 ;;
  esac
  out="$(prl "$verb" "$1" 2>&1)" ||
    log "WARN   could not return $1 to '$2': $(printf '%s' "$out" | tr '\n\r' '  ' | head -c 200)"
}

# Wait until the VM runs and answers through Parallels Tools.
# On timeout, logs the last VM state and the last 'prlctl exec' result.
wait_ready() { # ref
  local waited=0 st="" out="" rc=""
  while [ "$waited" -lt "$READY_TIMEOUT" ]; do
    st="$(vm_state "$1")"
    if [ "$st" = "running" ]; then
      out="$(prl exec "$1" cmd /c hostname 2>&1)"
      rc=$?
      out="$(printf '%s' "$out" | tr -d '\r' | head -c 300)"
      if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
        return 0
      fi
    fi
    sleep 5
    waited=$((waited + 5))
  done
  log "       last VM state='$st', last 'prlctl exec' rc='${rc:-none}', output='${out:-}'"
  return 1
}

active_name() { vm_exec "$1" cmd /c hostname; }

# Name stored for the next boot (differs from active_name while a restart is pending).
pending_name() {
  vm_exec "$1" cmd /c reg query 'HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' /v ComputerName |
    awk '/REG_SZ/ {print $NF; exit}'
}

boot_time() { ps_exec "$1" "(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('o')"; }

in_domain() { [ "$(ps_exec "$1" '(Get-CimInstance Win32_ComputerSystem).PartOfDomain')" = "True" ]; }

# Restart the VM and wait until Windows is back with a new boot time, so the old
# session, still answering while it shuts down, is not taken for the new one.
restart_vm() { # ref
  local before now waited=0
  before="$(boot_time "$1")"
  prl restart "$1" >/dev/null 2>&1 || return 1
  while [ "$waited" -lt "$READY_TIMEOUT" ]; do
    sleep 5
    waited=$((waited + 5))
    now="$(boot_time "$1")"
    [ -n "$now" ] && [ "$now" != "$before" ] && return 0
  done
  return 1
}

# ------------------------------------------------------------- per-VM work ---

# Returns 1 when the VM failed (now or in an earlier run still within RETRY_AFTER).
process_vm() { # id name state tools desired [number]
  local id="$1" name="$2" orig="$3" tools="$4" desired="$5" n="${6:-}"
  local ref="{$id}" active pending restart=false status kind
  local s_name s_status s_time
  local intro="Jamf is renaming the Windows computer in \"$name\" to $desired.${NL}${NL}"

  # stopped: nobody is in it. running: the user may be. parked (paused/suspended): the
  # window is closed, but a Windows session, possibly with unsaved work, is frozen inside.
  case "$orig" in
    stopped) kind=stopped ;;
    paused | suspended) kind=parked ;;
    running) kind=running ;;
    *)
      log "SKIP   '$name' ($id): VM is '$orig'; will retry at the next run"
      return 0
      ;;
  esac

  case "$tools" in
    installed | outdated) ;;
    *)
      log "SKIP   '$name' ($id): Parallels Tools not ready (state: $tools); will retry"
      state_put "$id" "$desired" "$n" "waiting-for-tools"
      return 0
      ;;
  esac

  if [ "$DRY_RUN" = "true" ]; then
    if [ "$kind" = "running" ]; then
      active="$(active_name "$ref")"
      pending="$(pending_name "$ref")"
      in_domain "$ref" && status="yes" || status="no"
      log "DRYRUN '$name' ($id): active='$active' pending='$pending' desired='$desired' domain-joined=$status"
    else
      log "DRYRUN '$name' ($id): state=$orig; would start/resume it to rename to '$desired'"
    fi
    return 0
  fi

  # What an earlier run recorded for this VM and this name.
  IFS=$'\t' read -r s_name s_status s_time _ <<<"$(state_get "$id")"
  if [ "${s_name:-}" = "$desired" ]; then
    case "$s_status" in
      ok | renamed | pending-restart)
        # Do not wake a stopped, paused or suspended VM (and notify the user) just to confirm.
        if [ "$kind" != "running" ]; then
          log "SKIP   '$name' ($id): $orig, already handled for '$desired' by an earlier run ($s_status)"
          return 0
        fi
        ;;
      failed-domain-joined)
        log "SKIP   '$name' ($id): joined to a domain; rename it through the domain (see the script header)"
        return 1
        ;;
      failed-*)
        if [ $(($(date +%s) - ${s_time:-0})) -lt "$RETRY_AFTER" ]; then
          log "SKIP   '$name' ($id): failed at an earlier run ($s_status); next try $((RETRY_AFTER / 3600))h after that run"
          return 1
        fi
        ;;
    esac
  fi

  log "START  '$name' ($id): power state '$orig' ($kind), Parallels Tools '$tools'"

  if [ "$kind" = "stopped" ]; then
    notify_user "Updating your Windows VM name" \
      "${intro}The VM will start in the background and shut down again when it is done. You may see Windows flicker."
  elif [ "$kind" = "parked" ]; then
    notify_user "Updating your Windows VM name" \
      "${intro}Your VM is $orig. It will wake briefly in the background and go back to $orig. You may see Windows flicker. The new name applies the next time you restart Windows."
  fi

  if ! bring_up "$ref" "$orig"; then
    log "FAIL   '$name' ($id): could not start/resume the VM (it was '$orig'): $BRING_UP_ERR"
    state_put "$id" "$desired" "$n" "failed-start"
    return 1
  fi
  if ! wait_ready "$ref"; then
    log "FAIL   '$name' ($id): VM did not answer through Parallels Tools within ${READY_TIMEOUT}s"
    restore_state "$ref" "$orig"
    state_put "$id" "$desired" "$n" "failed-not-ready"
    return 1
  fi

  active="$(active_name "$ref")"
  pending="$(pending_name "$ref")"

  if [ "$(lc "$active")" = "$(lc "$desired")" ]; then
    log "OK     '$name' ($id): already named '$active'"
    restore_state "$ref" "$orig"
    state_put "$id" "$desired" "$n" "ok"
    return 0
  fi

  if in_domain "$ref"; then
    log "FAIL   '$name' ($id): Windows is joined to a domain; renaming needs domain credentials, which this script does not hold. Rename it through the domain."
    restore_state "$ref" "$orig"
    state_put "$id" "$desired" "$n" "failed-domain-joined"
    return 1
  fi

  # stopped: restart, nobody is in it. running: restart only with REBOOT=now.
  # parked: never restart, it would discard the user's frozen Windows session.
  case "$kind" in
    stopped) restart=true ;;
    running) [ "$REBOOT" = "now" ] && restart=true ;;
  esac

  # Rename first, so the user is never warned of a restart for a rename that failed.
  if [ "$(lc "$pending")" != "$(lc "$desired")" ]; then
    log "RENAME '$name' ($id): '$active' -> '$desired'"
    # $desired passed valid_name in main (letters, digits, hyphens), so it is safe inside the quotes.
    ps_exec "$ref" "Rename-Computer -NewName '$desired' -Force -WarningAction SilentlyContinue" >/dev/null
    pending="$(pending_name "$ref")"
    if [ "$(lc "$pending")" != "$(lc "$desired")" ]; then
      log "FAIL   '$name' ($id): rename command did not take effect (pending name: '$pending')"
      restore_state "$ref" "$orig"
      state_put "$id" "$desired" "$n" "failed-rename"
      return 1
    fi
  elif [ "$kind" = "running" ] && [ "$restart" != "true" ]; then
    # Staged by an earlier run and still waiting for the user's restart: nothing new to say.
    log "STAGED '$name' ($id): '$desired' is staged, restart still pending"
    state_put "$id" "$desired" "$n" "pending-restart"
    return 0
  else
    log "STAGED '$name' ($id): '$desired' is staged, restart still pending"
  fi

  # Running: the user may be working in Windows. Warn first and give them
  # COUNTDOWN seconds to save their work; a restart closes their apps.
  if [ "$kind" = "running" ]; then
    if [ "$restart" != "true" ]; then
      notify_user "Your Windows VM name has been updated" \
        "${intro}No restart is needed now: the new name applies the next time you restart Windows."
    elif [ "$COUNTDOWN" -gt 0 ]; then
      notify_user "Your Windows VM will restart" \
        "${intro}Please save your work in Windows. The VM restarts to apply the new name when the countdown ends." "$COUNTDOWN"
      sleep "$COUNTDOWN"
    else
      notify_user "Your Windows VM will restart" "${intro}The VM restarts now to apply the new name."
    fi
  fi

  if [ "$restart" = "true" ]; then
    log "RESTART '$name' ($id)"
    if restart_vm "$ref" && [ "$(lc "$(active_name "$ref")")" = "$(lc "$desired")" ]; then
      log "DONE   '$name' ($id): now '$desired'"
      restore_state "$ref" "$orig"
      state_put "$id" "$desired" "$n" "renamed"
      return 0
    fi
    log "FAIL   '$name' ($id): Windows did not come back with the name '$desired' within ${READY_TIMEOUT}s of the restart"
    restore_state "$ref" "$orig"
    state_put "$id" "$desired" "$n" "failed-after-restart"
    return 1
  fi

  log "PENDING '$name' ($id): '$desired' applies at the next Windows restart"
  restore_state "$ref" "$orig"
  state_put "$id" "$desired" "$n" "pending-restart"
  return 0
}

# -------------------------------------------------------------------- main ---

main() {
  case "$REBOOT" in now | defer) ;; *) echo "Invalid REBOOT '$REBOOT' (now|defer)"; exit 2 ;; esac
  case "$DRY_RUN" in true | false) ;; *) echo "Invalid DRY_RUN '$DRY_RUN' (true|false)"; exit 2 ;; esac
  if [[ ! "$COUNTDOWN" =~ ^[0-9]{1,4}$ ]] || [ "$COUNTDOWN" -gt 3600 ]; then
    echo "Invalid COUNTDOWN '$COUNTDOWN' (0-3600 seconds)"
    exit 2
  fi
  if [ -n "$VM_FILTER" ]; then
    printf '' | grep -Eq -e "$VM_FILTER" 2>/dev/null
    if [ $? -eq 2 ]; then
      echo "Invalid VM_FILTER '$VM_FILTER' (not an extended regular expression)"
      exit 2
    fi
  fi

  mkdir -p "$STATE_DIR" 2>/dev/null
  if ! acquire_lock; then
    log "Another run is in progress (pid $(cat "$LOCK_DIR/pid" 2>/dev/null)); exiting"
    exit 0
  fi
  trap 'rm -rf "$LOCK_DIR"' EXIT

  CONSOLE_USER="$(stat -f%Su /dev/console 2>/dev/null)"
  if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || [ "$CONSOLE_USER" = "loginwindow" ]; then
    log "No user logged in at the console; nothing to do"
    exit 0
  fi

  for p in /usr/local/bin/prlctl "/Applications/Parallels Desktop.app/Contents/MacOS/prlctl"; do
    [ -x "$p" ] && PRLCTL="$p" && break
  done
  if [ -z "$PRLCTL" ]; then
    log "prlctl not found; is Parallels Desktop installed?"
    exit 0
  fi

  local serial desired plain json vms matches count id name state tools n s_name taken=" " numbered_list rc=0
  serial="$(get_serial)"
  if [ -z "$serial" ]; then
    log "Could not read the Mac serial number"
    exit 1
  fi
  if ! desired="$(render_name "$NAME_PATTERN" "$serial" 1)"; then
    log "Invalid NAME_PATTERN '$NAME_PATTERN' (it must contain {serial})"
    exit 2
  fi
  if ! valid_name "$desired"; then
    log "NAME_PATTERN '$NAME_PATTERN' gives '$desired' (${#desired} characters), which is not a valid Windows computer name (1-15 letters, digits or hyphens, no hyphen at either end, not all digits)"
    exit 2
  fi
  plain="$desired"
  log "Start: user=$CONSOLE_USER pattern='$NAME_PATTERN' reboot=$REBOOT countdown=${COUNTDOWN}s dry_run=$DRY_RUN filter='$VM_FILTER' name='$plain'"

  check_edition || exit 1

  if ! json="$(prl list -a -i --json 2>/dev/null)"; then
    log "FAIL   'prlctl list' did not work; cannot read the VMs"
    exit 1
  fi
  if ! vms="$(printf '%s' "$json" | windows_vms_from_json)"; then
    log "FAIL   could not read the VM list returned by 'prlctl list'"
    exit 1
  fi

  matches=""
  while IFS=$'\t' read -r id name state tools; do
    [ -n "$id" ] || continue
    if [ -n "$VM_FILTER" ] && ! printf '%s' "$name" | grep -Eq -e "$VM_FILTER"; then
      continue
    fi
    matches="${matches}${id}"$'\t'"${name}"$'\t'"${state}"$'\t'"${tools}${NL}"
  done <<<"$vms"
  count="$(printf '%s' "$matches" | grep -c .)"

  if [ "$count" -eq 0 ]; then
    log "No Windows VM found${VM_FILTER:+ matching VM_FILTER '$VM_FILTER'}"
    exit 0
  fi
  # Number the VMs: number 1 gets the plain name, 2 and up add the number
  # (render_name). A single VM is always 1. With several, in VM name order, first
  # pass: each VM keeps the number an earlier run recorded for it, unless a VM
  # listed before it holds it; a record from before numbering (no number) counts
  # as 1 when it holds the plain name. Second pass: the others get the lowest free
  # number. So adding or deleting a VM does not rename (and restart) the others.
  # Lines are number<TAB>id<TAB>name<TAB>state<TAB>tools, with '-' for no number
  # yet (tab-separated 'read' would drop an empty first field).
  numbered_list=""
  while IFS=$'\t' read -r id name state tools; do
    [ -n "$id" ] || continue
    n=1
    if [ "$count" -gt 1 ]; then
      IFS=$'\t' read -r s_name _ _ n <<<"$(state_get "$id")"
      [ -z "$n" ] && [ -n "$s_name" ] && [ "$s_name" = "$plain" ] && n=1
      if [[ "$n" =~ ^[1-9][0-9]{0,2}$ ]] && [[ "$taken" != *" $n "* ]]; then
        taken="$taken$n "
      else
        n="-"
      fi
    fi
    numbered_list="${numbered_list}${n}"$'\t'"${id}"$'\t'"${name}"$'\t'"${state}"$'\t'"${tools}${NL}"
  done <<<"$(printf '%s' "$matches" | sort -t$'\t' -k2,2)"

  # fd 3, so that nothing run for a VM can read the rest of the list.
  while IFS=$'\t' read -r -u 3 n id name state tools; do
    [ -n "$id" ] || continue
    if [ "$n" = "-" ]; then
      n=1
      while [[ "$taken" == *" $n "* ]]; do n=$((n + 1)); done
      taken="$taken$n "
    fi
    desired="$(render_name "$NAME_PATTERN" "$serial" "$n")"
    if ! valid_name "$desired"; then
      log "FAIL   '$name' ($id): number $n gives '$desired' (${#desired} characters), which is not a valid Windows computer name"
      rc=1
      continue
    fi
    process_vm "$id" "$name" "$state" "$tools" "$desired" "$n" || rc=1
  done 3<<<"$numbered_list"

  if [ "$rc" -eq 0 ]; then
    log "Finished"
  else
    log "Finished with a failure"
  fi
  return "$rc"
}

# Allow sourcing for tests; run main when executed.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
  exit $?
fi
