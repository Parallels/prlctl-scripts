#!/bin/zsh
 
# Get the current user. This part allows executing the script from the Mac Management tools.
CURRENT_USER=$(whoami)
 
# List all VMs, extract IDs, and disable pause-idle for each VM under the current user
# Feel free to update the command or have multiple commands in a row to change the settings you like.
# Learn more about changing the setting using "man prlctl". It can also do operations on VMs, like stop or delete.
for i in $(prlctl list -a --info | grep "ID: {" | sed 's/.....//;s/.$//'); do
    sudo -u "$CURRENT_USER" prlctl set "$i" --pause-idle off
done
