#!/bin/bash


while getopts ":o:t:p:" opt; do
  case $opt in
    p) PATH="$OPTARG"
    ;;
    t) TOKEN="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

if [ -z "$TOKEN" ]; then
  echo "Token is required"
  exit 1
fi


~/actions-runner/config.sh remove --token $TOKEN