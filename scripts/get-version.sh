#!/bin/bash

info=$(prlsrvctl info | awk -F ': ' '/^Version/ {print $2}')

if [[ $info ]]; then
  ##if info is present, return that
  echo "$info"

else
  ##if no info is present, return "Not Installed"
  echo "Not Installed"
fi

exit 0
