#!/bin/bash

/usr/local/bin/prlsrvctl info | awk -F ': ' '/^Version/ {print $2}'