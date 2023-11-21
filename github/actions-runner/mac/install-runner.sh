#!/bin/bash

# Create a folder
mkdir ~/actions-runner && cd ~/actions-runner
# Download the latest runner package
curl -o actions-runner-osx-arm64-2.309.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.309.0/actions-runner-osx-arm64-2.309.0.tar.gz
# Optional: Validate the hash
echo "67c1accb9cdc2138fc797d379c295896c01c8f5f4240e7e674f99a492bd1c668  actions-runner-osx-arm64-2.309.0.tar.gz" | shasum -a 256 -c
# Extract the installer
tar xzf actions-runner-osx-arm64-2.309.0.tar.gz