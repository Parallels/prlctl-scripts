#!/bin/bash
#set -x

process=$(/usr/local/bin/prlsrvctl info | awk -F ': ' '/^License/ {print $2}')
echo $process
