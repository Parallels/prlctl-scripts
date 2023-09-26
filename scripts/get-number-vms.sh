#!/bin/bash

/usr/local/bin/prlctl list -a | grep -oE '\{[a-f0-9\-]+\}' | wc -l | awk '{$1=$1};1'