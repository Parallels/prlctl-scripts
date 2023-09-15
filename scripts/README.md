# Bash Scripts

This folder contains bash scripts that can be used to automate the process of setting up a local development environment for a project.

## Prerequisites

- [Parallels Desktop](https://www.parallels.com/products/desktop/)

## Usage

1. Clone this repository to your local machine.
2. Open the terminal and navigate to the folder containing the scripts.
3. Run the script you want to use.

## Scripts

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