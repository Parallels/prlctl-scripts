#!/bin/bash

USERNAME=""
NEW_PASSWORD=""

while [[ $# -gt 0 ]]; do
  case $1 in
  --username)
    USERNAME="$2"
    shift
    shift
    ;;
  --new-password)
    NEW_PASSWORD="$2"
    shift
    shift
    ;;
  *)
    echo "Invalid option $1" >&2
    exit 1
    ;;
  esac
done

echo "Enabling Remote VNC"
cd /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/ || exit
sudo ./kickstart -activate -configure -access -on \
  -clientopts -setvnclegacy -vnclegacy yes \
  -clientopts -setvncpw -clientopts -setreqperm -reqperm yes
sudo ./kickstart -configure -allowAccessFor -specifiedUsers
sudo ./kickstart -configure -allowAccessFor -allUsers -privs -all
sudo ./kickstart -activate

# Disable sleep
echo "Disabling sleep"
sudo systemsetup -setcomputersleep Off
sudo systemsetup -setcomputersleep Off || true
sudo pmset -a standby 0

# Disable disk sleep
echo "Disabling disk sleep"
sudo pmset -a disksleep 0

# Hibernate mode is a problem on some mac minis; best to just disable
echo "Disabling hibernate mode"
sudo pmset -a hibernatemode 0

# Disable indexing volumes
echo "Disabling indexing volumes"
sudo defaults write ~/.Spotlight-V100/VolumeConfiguration.plist Exclusions -array "/Volumes"
sudo defaults write ~/.Spotlight-V100/VolumeConfiguration.plist Exclusions -array "/Network"
sudo killall mds
sleep 60

# Make sure indexing is DISABLED for the main volume
echo "Disabling indexing"
sudo mdutil -a -i off /
sudo mdutil -a -i off

# Disable Time Machine
echo "Disabling Time Machine"
sudo tmutil disable

# Disable the screensaver
echo "Disabling the screensaver"
sudo defaults -currentHost write com.apple.screensaver idleTime 0

# Disable the screensaver password
echo "Disabling the screensaver password"
sudo defaults -currentHost write com.apple.screensaver askForPassword -int 0

# Disable the screensaver password delay
echo "Disabling the screensaver password delay"
sudo defaults -currentHost write com.apple.screensaver askForPasswordDelay -int 0

if [[ -n "$USERNAME" ]]; then
  echo "Creating user $USERNAME and setting password"
  sudo dscl . -passwd /Users/$USERNAME "$NEW_PASSWORD"
  sudo dscl . -create /Users/$USERNAME Picture "/Library/User Pictures/Nature/Earth.png"
  sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -configure -access -on -users $USERNAME -privs -all -restart -agent -menu
fi
