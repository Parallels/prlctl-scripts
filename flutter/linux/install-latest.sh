#!/bin/bash

# Check if Flutter is already installed
if command -v flutter &> /dev/null; then
  echo "Flutter is already installed."
  exit 0
fi

# Download the latest Flutter SDK
echo "Downloading Flutter SDK..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1 ~/.flutter

# Add Flutter to the PATH
echo "Adding Flutter to the PATH..."
echo 'export PATH="$PATH:$HOME/.flutter/bin"' >> ~/.bashrc
source ~/.bashrc

# Run Flutter doctor to verify the installation
echo "Verifying Flutter installation..."
flutter doctor

echo "Flutter installation completed successfully."
