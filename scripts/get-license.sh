#!/bin/bash

/usr/local/bin/prlsrvctl info | awk -F ': ' '/^License/ {print $2}'