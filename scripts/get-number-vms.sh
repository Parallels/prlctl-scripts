#!/bin/bash

user_count=$(/usr/local/bin/prlctl list -a | grep -oE '\{[a-f0-9\-]+\}' | wc -l | awk '{$1=$1};1')

if [[ $user_count ]]; then
  echo "$user_count"
else
  echo "No VMs found"
fi

exit 0
