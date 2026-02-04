#!/bin/bash
# The script is handy when you deploy Parallels Desktop with a virtual machine 
# set to run in Coherence mode. The scripts hides the Parallels interface, 
# you can use it to hide the Parallels icon in the menu bar, 
# hide the Parallels icon in the menu bar, 
# hide the Coherence walkthrough
# You can run the script as part of the Parallels Desktop deployment process. 
# Put it after the Parallels Desktop package instalaltion in the policy or use Smart Groups.

# Safety check
PRL_PATH="/Applications/Parallels Desktop.app"
if [ ! -d "$PRL_PATH" ]; then
    echo "Parallels Desktop is not installed at $PRL_PATH"
    exit 1
fi

# hide Windows icon in the dock
defaults write com.parallels.Parallels\ Desktop "Application preferences.Dock icon" 2

# hide Parallels icon in the menu bar
defaults write com.parallels.Parallels\ Desktop "Application preferences.Show Tray Icon" 0

# hide Coherence walkthrough
defaults write com.parallels.Parallels\ Desktop "Hidden Messages ID List.15077" 1