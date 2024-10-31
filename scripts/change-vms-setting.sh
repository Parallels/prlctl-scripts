#!/bin/zsh
 
# Get the current user
CURRENT_USER=$(whoami)
 
# List all VMs, extract IDs, and disable pause-idle for each VM under the current user
for i in $(prlctl list -a --info | grep "ID" | sed 's/.....//;s/.$//'); do
    sudo -u "$CURRENT_USER" prlctl set "$i" --pause-idle off
done