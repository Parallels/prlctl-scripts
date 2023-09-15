#/bin/bash

prlsrvctl info | awk -F ': ' '/^Version/ {print $2}'