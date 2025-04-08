#!/bin/bash

edition=$(prlsrvctl info --license | awk -F '=' '/edition/ {gsub(/"/, "", $2); print $2}')

if [[ $edition ]]; then
  echo "$edition"
else
  echo "No Edition found"
fi

exit 0
