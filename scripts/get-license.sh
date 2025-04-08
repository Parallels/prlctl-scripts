#!/bin/bash

license=$(prlsrvctl info | awk -F ': ' '/^License/ {print $2}')

if [[ $license ]]; then
  echo "$license"
else
  echo "No License found"
fi

exit 0
