#!/bin/bash
#set -x

process=$(/usr/local/bin/prlsrvctl info | awk -F ': ' '/^Version/ {print $2}')
echo $process