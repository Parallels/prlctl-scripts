#!/bin/bash

prlsrvctl set --require-pwd add-vm:on && prlcrvctl set --require-pwd create-vm:on && prlcrvctl set
--require-pwd clone-vm:on

if [[ $? -eq 0 ]]; then
  echo "Success"
else
  echo "Failed"
fi

exit 0
