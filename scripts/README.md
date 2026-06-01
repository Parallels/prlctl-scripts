# Bash Scripts

This folder contains bash scripts that can be used to automate the process of managing Parallels Desktop virtual machines.

## Prerequisites

- [Parallels Desktop](https://www.parallels.com/products/desktop/)

## Usage

1. Clone this repository to your local machine.
2. Open the terminal and navigate to the folder containing the scripts.
3. Run the script you want to use.

## Scripts

### `change-vms-setting.sh`

This will go through all the VMs the current user has registered and apply specified settings or actions.

### `execute_on_windows_vm.sh`

Executes a command inside a running Windows VM using either `cmd` or PowerShell (`pwsh`) mode.

Requirements: `prlctl`, `jq`

```bash
./execute_on_windows_vm.sh --mode cmd --name "VM Name" --command "echo test"
./execute_on_windows_vm.sh --mode pwsh --name "VM Name" --command "Get-Date"
./execute_on_windows_vm.sh --mode cmd --name "VM Name" --command "echo test" --verbose
```

### `get-edition.sh`

Returns the edition of Parallels Desktop (e.g. Pro, Business).

```bash
./get-edition.sh
```

### `get-license.sh`

Returns the type of license currently in use with Parallels Desktop.

### `get-machines.sh`

Returns a list of all VMs for the current user. Use `-s` to filter by status and `-f` to change the output format.

```bash
./get-machines.sh -s running
./get-machines.sh -f csv
```

### `get-machines-all-users.sh`

Returns a list of all VMs across all local macOS users. Supports the same `-s` and `-f` options as `get-machines.sh`.

```bash
./get-machines-all-users.sh -s running -f csv
```

### `get-number-vms.sh`

Returns how many VMs exist for the current user.

### `get-number-vms-all-users.sh`

Returns how many VMs exist across all local macOS users. Use `-s` to filter by status.

```bash
./get-number-vms-all-users.sh -s running
```

### `get-running-machines.sh`

Returns all currently running VMs across all local macOS users. Use `-f` to change the output format.

```bash
./get-running-machines.sh
./get-running-machines.sh -f csv
```

### `get-stopped-machines.sh`

Returns all stopped VMs across all local macOS users. Use `-f` to change the output format.

```bash
./get-stopped-machines.sh
./get-stopped-machines.sh -f csv
```

### `get-suspended-machines.sh`

Returns all suspended VMs across all local macOS users. Use `-f` to change the output format.

```bash
./get-suspended-machines.sh
./get-suspended-machines.sh -f csv
```

### `get-version.sh`

Returns the version of Parallels Desktop.

### `hide-parallels-interface.sh`

Hides Parallels Desktop UI elements to create a cleaner deployment experience when running VMs in Coherence mode. Sets the following defaults:

- Hides the Windows icon in the Dock
- Hides the Parallels icon in the menu bar
- Hides the Coherence mode walkthrough

Run this script as part of a Parallels Desktop deployment policy (e.g. after the package installation step in Jamf or Intune).

```bash
./hide-parallels-interface.sh
```

### `suspend-machines-on-close-lid.sh`

This script must be *installed* before it can be used. It runs in the background and listens for the lid-close event, then suspends all running VMs automatically.

```bash
# Install
./suspend-machines-on-close-lid.sh -i

# Uninstall
./suspend-machines-on-close-lid.sh -u
```

### `restrict-operations-add-create-clone.sh`

Restricts the add, create, and clone operations on VMs.

```bash
./restrict-operations-add-create-clone.sh
```

### `windows_vms_update.sh`

Checks for and installs Windows Updates on all running Windows VMs.

```bash
./windows_vms_update.sh --help
```

Available actions:

- `list-updates`: list available updates for all Windows VMs
- `install`: install updates on all Windows VMs
- `check`: check whether updates are available
- `uninstall`: uninstall updates
- `check-and-install`: check and install updates in one step

### `get-bitlocker-status.sh`

Checks BitLocker status (C: drive) in Windows Parallels VMs for the console macOS user.
The guest-side query uses `manage-bde -status C:`.

Output per VM: `<VM Name>: Protection Status: <status>`

Usage examples:

```bash
./get-bitlocker-status.sh
./get-bitlocker-status.sh --vm "Windows 11"
./get-bitlocker-status.sh --silent
./get-bitlocker-status.sh --verbose
```

Optional flags:

- `--vm`: target a specific VM by name or UUID
- `--silent`: only check already-running VMs; do not start or resume non-running VMs
- `--verbose`: print extra diagnostics when status cannot be determined

### `suspend-bitlocker-one-reboot.sh`

Suspends BitLocker protectors for one reboot on Windows Parallels VMs across all local macOS users.
Designed for MDM/root execution. Uses the guest command:

- `manage-bde -protectors -disable C: -RebootCount 1`

By default, only running Windows VMs are processed.

Usage examples:

```bash
./suspend-bitlocker-one-reboot.sh
./suspend-bitlocker-one-reboot.sh --run-non-running
./suspend-bitlocker-one-reboot.sh --vm-id "<VM UUID or Name>"
./suspend-bitlocker-one-reboot.sh --format json
```

Optional flags:

- `--run-non-running`: start/resume non-running Windows VMs, run the BitLocker suspend action, then suspend them again
- `--drive`: target a different Windows drive letter (default `C:`)
- `--format`: `text` (default), `json`, or `csv`
- `--verbose`: enable detailed logging

### `check-secureboot-certificates.sh`

Runs this PowerShell expression inside each running Windows VM:

```powershell
([System.Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI db).bytes) -match "Windows UEFI CA 2023")
```

Output per VM:

- `False` => `X SecureBoot certificates require update`
- `True` => `V SecureBoot certificates are up to date`

Usage examples:

```bash
./check-secureboot-certificates.sh
./check-secureboot-certificates.sh --vm "Windows 11"
./check-secureboot-certificates.sh --run-non-running
./check-secureboot-certificates.sh --vm "Windows 11 Work" --verbose
```

Optional flags:

- `--run-non-running`: start/resume non-running Windows VMs, check, then suspend them
- `--verbose`: show raw command output when status cannot be determined

### `get-secureboot-pk-status.sh`

Reports SecureBoot PK certificate status for Windows 11 Parallels VMs belonging to the console user.
Reads the PK certificate hash from `VmInfo.pvi` (written by Parallels Tools >= 26.3.3) without starting or modifying any VMs.

Requirements: Parallels Desktop >= 26.3.3

Output:

- `All VMs have updated certificates`
- `One or more VMs have outdated certificates`
- `Waiting for Parallels Tools to be updated on one or more VMs`

Usage examples:

```bash
./get-secureboot-pk-status.sh
./get-secureboot-pk-status.sh --vm "Windows 11"
./get-secureboot-pk-status.sh --verbose
```

### `update-secureboot-certificates.sh`

Updates SecureBoot PK certificates in Windows 11 Parallels VMs belonging to the console user.
Reads the PK certificate hash from `VmInfo.pvi` (requires Parallels Tools >= 26.3.3) and takes one of two actions:

- **Parallels Tools need updating** (no PK hash in `VmInfo.pvi`): starts the VM if not running and triggers `prlctl installtools`
- **PK certificate hash is outdated**: suspends BitLocker if active, restarts Windows to apply the certificate update, then polls `VmInfo.pvi` to confirm success

Requirements: Parallels Desktop >= 26.3.3

Usage examples:

```bash
./update-secureboot-certificates.sh
./update-secureboot-certificates.sh --silent
./update-secureboot-certificates.sh --vm "Windows 11"
./update-secureboot-certificates.sh --verbose
```

Optional flags:

- `--silent`: skip starting non-running VMs; only process already-running VMs
- `--vm`: target a specific VM by name or UUID
- `--verbose`: enable detailed logging
