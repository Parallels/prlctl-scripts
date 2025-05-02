# Bash Scripts

This folder contains bash scripts that can be used to automate the process of setting up a local development environment for a project.

## Prerequisites

- [Parallels Desktop](https://www.parallels.com/products/desktop/)

## Usage

1. Clone this repository to your local machine.
2. Open the terminal and navigate to the folder containing the scripts.
3. Run the script you want to use.

## Scripts

### `change-vms-settings`

This will go through all the VMs the current user has registered and apply specified settings or actions.

### `get-license`

This will return what type of license you are using with PD

### `get-machines`

this will return a list of all the VMs on your machine, you can use -s to filter by status, example

```bash
./get-machines -s running
```

we can also use the -f to display it as csv

```bash
./get-machines -f csv
```

### `get-number-vms`

returns how many VMs exist in the backend

### `get-version`

returns the version of PD

### `suspend-machines-on-close-lid`

This script will need to be *installed* before it can be used as it will run in the background and listen for the lid closing event. To install it, run the following command:

```bash
./suspend-machines-on-close-lid -i
```

Once it is installed it will run in the background and it will suspend all running VMs when the lid is closed. To uninstall it, run the following command:

```bash
./suspend-machines-on-close-lid -u
```

### `restrict-operations-add-create-clone`

This script will restrict the operations that can be performed on the VMs.

```bash
./restrict-operations-add-create-clone
```

### `windows_vms_update.sh`

This script will check for updates for all the Windows VMs and install them.

```bash
./windows_vms_update.sh --help
```

this will show the help menu, the options are:

- `list-updates`: list the updates for all the Windows VMs
- `install`: install the updates for all the Windows VMs
- `check`: check if there are updates for all the Windows VMs
- `uninstall`: uninstall the updates for all the Windows VMs
- `check-and-install`: check and install the updates for all the Windows VMs
