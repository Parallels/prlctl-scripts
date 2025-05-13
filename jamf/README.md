# Parallels Desktop VM Management for Jamf

This repository contains scripts and extensions for managing Parallels Desktop virtual machines through Jamf Pro.

## Overview

These scripts allow administrators to manage Windows VMs running in Parallels Desktop through Jamf Pro, including:

- Checking for and installing Windows updates
- Executing commands on Windows VMs
- Managing Parallels Desktop Guest Tools

## Scripts

### windows_vms_update.sh

A comprehensive script for managing Windows updates in Parallels Desktop VMs.

**Features:**

- Check for available Windows updates
- List detailed update information
- Install specific or all available updates
- Uninstall specific updates
- Update Parallels Desktop Guest Tools
- Support for both interactive and unattended operation

**Usage:**

```bash
./windows_vms_update.sh [MODE] [OPTIONS]
```

**Modes:**

- `list-updates` - List available updates for Windows VMs
- `install` - Install updates for specified VMs
- `uninstall` - Uninstall specific updates (requires --kb)
- `check` - Check for available updates
- `check-and-install` - Check for and install available updates

### execute_on_windows_vm.sh

A utility script to execute commands on Windows VMs through either Command Prompt or PowerShell.

**Features:**

- Execute commands on one or multiple VMs
- Support for both CMD and PowerShell execution
- Detailed output and error reporting

**Usage:**

```bash
./execute_on_windows_vm.sh [OPTIONS]
```

**Example:**

```bash
./execute_on_windows_vm.sh --mode pwsh --name "Windows VM" --command "Get-Process"
```

## Requirements

- Parallels Desktop for Mac
- jq (automatically installed by scripts if not present)
- macOS with Jamf Pro management

## Installation

1. Upload the scripts to your Jamf Pro server
2. Create policies that execute these scripts with appropriate parameters
3. Scope the policies to computers with Parallels Desktop installed

## Extensions

The repository also includes extensions that can be used with Jamf Pro to enhance Parallels VM management capabilities.
