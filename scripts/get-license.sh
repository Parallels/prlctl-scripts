#/bin/bash

prlsrvctl info | awk -F ': ' '/^License/ {print $2}'