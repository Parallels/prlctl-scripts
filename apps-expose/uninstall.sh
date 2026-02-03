#!/bin/bash

# uninstall.sh
# Removes the Parallels Windows Apps Exposure Service

echo "Stopping and removing Parallels Apps Expose Service..."

# 1. Unload LaunchAgent for current user
CURRENT_USER=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
USER_ID=$(id -u "$CURRENT_USER")

if [[ -n "$CURRENT_USER" ]]; then
    echo "Unloading agent for user: $CURRENT_USER"
    launchctl bootout gui/$USER_ID /Library/LaunchAgents/com.company.parallels-apps-expose-service.plist 2>/dev/null
fi

# 2. Remove Files
echo "Removing files..."
rm -f /usr/local/bin/parallels_apps_expose_service.sh
rm -f /Library/LaunchAgents/com.company.parallels-apps-expose-service.plist

# 3. Cleanup Logs (Optional - good for complete wipe)
# rm -rf "$HOME/Library/Logs/ParallelsAppsExposeService"
# Since script runs as root usually during uninstall, $HOME might be tricky. 
# We'll leave user logs as is or delete for specific user if needed.
# Below attempts to clean for the current user safely.
if [[ -n "$CURRENT_USER" ]]; then
    USER_HOME=$(dscl . -read /Users/$CURRENT_USER NFSHomeDirectory | awk '{print $2}')
    if [[ -d "$USER_HOME/Library/Logs/ParallelsAppsExposeService" ]]; then
        echo "Removing logs..."
        rm -rf "$USER_HOME/Library/Logs/ParallelsAppsExposeService"
    fi
     # Cleanup created "Windows Apps" folder?
    # PRD says "Remove created shortcuts", but "Preserves original Parallels app bundles".
    # The agent removes shortcuts on stop? No, only on 'sync'.
    # So we should probably remove the "Windows Apps" folder to be clean.
    if [[ -d "$USER_HOME/Applications (Parallels)/Windows Apps" ]]; then
        echo "Removing Windows Apps folder..."
        rm -rf "$USER_HOME/Applications (Parallels)/Windows Apps"
    fi
    
    # Remove from Dock
    # We must run this as the user
    echo "Removing 'Windows Apps' from Dock configuration..."
    
    sudo -u "$CURRENT_USER" bash <<'EOF'
    dock_plist="$HOME/Library/Preferences/com.apple.dock.plist"
    
    # Check if plist exists
    if [[ ! -f "$dock_plist" ]]; then
        exit 0
    fi

    # Find and Delete
    COUNT=$(/usr/libexec/PlistBuddy -c "Print persistent-others" "$dock_plist" 2>/dev/null | grep -c "Dict")
    
    REMOVED=false
    
    if [[ "$COUNT" =~ ^[0-9]+$ ]]; then
        for ((i=COUNT-1; i>=0; i--)); do
            # Get Data
            LABEL=$(/usr/libexec/PlistBuddy -c "Print persistent-others:$i:tile-data:file-label" "$dock_plist" 2>/dev/null)
            VAL=$(/usr/libexec/PlistBuddy -c "Print persistent-others:$i:tile-data:file-data:_CFURLString" "$dock_plist" 2>/dev/null)
            
            IS_MATCH=false
            if [[ "$LABEL" == "Windows Apps" ]]; then
                IS_MATCH=true
            elif [[ "$VAL" == *"Windows Apps"* ]]; then
                 IS_MATCH=true
            fi

            if [[ "$IS_MATCH" == "true" ]]; then
                echo "Removing Dock Item at index $i (Label: $LABEL)"
                /usr/libexec/PlistBuddy -c "Delete persistent-others:$i" "$dock_plist"
                REMOVED=true
            fi
        done
        
        if [[ "$REMOVED" == "true" ]]; then
             echo "Restarting Dock..."
             killall Dock
        fi
    fi
EOF
fi

# 4. Forget package receipt (if installed via pkg)
pkgutil --forget com.company.parallels-apps-expose-service 2>/dev/null

echo "Uninstall complete."
