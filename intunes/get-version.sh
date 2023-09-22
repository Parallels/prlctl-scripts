#!/bin/bash
#set -x

process=$(prlsrvctl info | awk -F ': ' '/^Version/ {print $2}')
echo $process