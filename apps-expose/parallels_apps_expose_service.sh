#!/bin/bash

# Parallels Windows Apps Exposure Service
# Monitors Parallels VM applications and exposes them to a Dock-visible folder.

# ==============================================================================
# Configuration
# ==============================================================================

# Directory where Parallels stores VM application stubs
: "${SOURCE_ROOT:=$HOME/Applications (Parallels)}"

# Directory where we will expose the filtered apps
DEST_DIR="$SOURCE_ROOT/Windows Apps"

# Log file path
: "${LOG_FILE:=$HOME/Library/Logs/ParallelsAppsExposeService/service.log}"

# Poll interval in seconds
: "${POLL_INTERVAL:=60}"

# Applications to exclude (grep patterns)
# Applications to exclude
# Add each app as a separate line in the array
# These are treated as Regex patterns.
EXCLUDED_APPS=(
    "Calculator"
    "Camera"
    "Character Map"
    "Click to Do \(preview\)"
    "Clock"
    "Command Prompt"
    "Copilot"
    "Defragment and Optimize Drives"
    "Dev Home"
    "Disk Cleanup"
    "Feedback Hub"
    "File Explorer"
    "File Picker UI Host"
    "Game Bar"
    "Get Help"
    "Get Started"
    "Live captions"
    "Magnifier"
    "Media Player"
    "Microsoft 365 \(Office\)"
    "Microsoft Clipchamp"
    "Microsoft Edge"
    "Microsoft News"
    "Microsoft Store"
    "Microsoft Teams"
    "Microsoft To Do"
    "Narrator"
    "Notepad"
    "ODBC Data Sources \(32-bit\)"
    "On-Screen Keyboard"
    "Outlook"
    "Paint"
    "Phone Link"
    "Photos"
    "Quick Assist"
    "Recovery Drive"
    "Registry Editor"
    "Remote Desktop Connection"
    "Resource Monitor"
    "rgnupdt"
    "Settings"
    "Snipping Tool"
    "Solitaire & Casual Games"
    "Sound Recorder"
    "Steps Recorder"
    "Sticky Notes"
    "System Configuration"
    "System Information"
    "Task Manager"
    "Terminal"
    "Voice access"
    "Weather"
    "Windows Backup"
    "Windows Media Player Legacy"
    "Windows PowerShell"
    "Windows PowerShell \(x86\)"
    "Windows PowerShell ISE"
    "Windows PowerShell ISE \(x86\)"
    "Windows Security"
)

# ==============================================================================
# Helpers
# ==============================================================================

DEFAULT_LOG_DIR=$(dirname "$LOG_FILE")
if [[ ! -d "$DEFAULT_LOG_DIR" ]]; then
    mkdir -p "$DEFAULT_LOG_DIR"
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

ensure_dest_dir() {
    if [[ ! -d "$DEST_DIR" ]]; then
        log "Creating destination directory: $DEST_DIR"
        mkdir -p "$DEST_DIR"
    fi
}

# Check if an app name matches any exclusion pattern
is_excluded() {
    local app_name="$1"
    local pattern
    
    # Strip .app for easier matching if present
    local clean_name="${app_name%.app}"
    
    for pattern in "${EXCLUDED_APPS[@]}"; do
        # Use ^ and $ to ensure exact match of the pattern against the clean name
        local regex="^${pattern}$"
        if [[ "$clean_name" =~ $regex ]]; then
            return 0 # True, it is excluded
        fi
    done
    return 1 # False, not excluded
}

# ==============================================================================
# Core Logic
# ==============================================================================

sync_apps() {
    local changed=0
    # Ensure destination directory exists at the start of every sync cycle
    # This prevents 'ln: .../Windows Apps/xxx: No such file or directory' if user deleted the folder.
    ensure_dest_dir

    # 1. CLEANUP SYMLINKS (Orphaned OR Excluded)
    if [[ -d "$DEST_DIR" ]]; then
        for link in "$DEST_DIR"/*.app; do
            # In bash, if no match, link is literally ".../*.app". 
            if [[ ! -e "$link" && ! -L "$link" ]]; then
                continue
            fi

            # If it's a symlink
            if [[ -L "$link" ]]; then
                link_name=$(basename "$link")
                
                # Check 1: Is it excluded?
                if is_excluded "$link_name"; then
                    log "Removing excluded link: $link_name"
                    rm "$link"
                    changed=1
                    continue
                fi

                # Check 2: Is it orphaned?
                target=$(readlink "$link")
                if [[ ! -e "$target" ]]; then
                    log "Removing orphaned link: $link_name"
                    rm "$link"
                    changed=1
                fi
            fi
        done
    fi

    # 2. DISCOVER AND LINK NEW APPS
    # Log the find command for debugging
    # Using -print0 to handle special characters correctly
    while IFS= read -r -d '' app_path; do
        
        # Skip if path contains DEST_DIR to prevent recursion
        if [[ "$app_path" == *"$DEST_DIR"* ]]; then
            continue
        fi

        app_name=$(basename "$app_path")
        
        # Check Exclusions using helper function
        if is_excluded "$app_name"; then
            continue
        fi

        # Find a stable name for this app (handling collisions)
        candidate_name="$app_name"
        counter=2
        while true; do
            dest_link="$DEST_DIR/$candidate_name"
            
            if [[ -L "$dest_link" ]]; then
                current_target=$(readlink "$dest_link")
                if [[ "$current_target" == "$app_path" ]]; then
                    # This link already points to this app. Stable.
                    break
                else
                    # Collision! This name is taken by another app path.
                    candidate_name="${app_name%.app} ($counter).app"
                    ((counter++))
                fi
            elif [[ -e "$dest_link" ]]; then
                 log "Warning: $dest_link exists but is not a symlink. Skipping this name."
                 candidate_name="${app_name%.app} ($counter).app"
                 ((counter++))
            else
                # Found a free name
                log "Exposing new app: $candidate_name"
                ln -s "$app_path" "$dest_link"
                changed=1
                break
            fi
            
            # Safety break to prevent infinite loop (unlikely but good practice)
            if [[ $counter -gt 50 ]]; then
                log "Error: Too many collisions for $app_name. Giving up."
                break
            fi
        done

    done < <(find "$SOURCE_ROOT" -mindepth 2 -name "*.app" -type d -print0)

    return $changed
}

manage_dock() {
    # Check if destination directory has content
    HAS_CONTENT=false
    if [[ -d "$DEST_DIR" && -n "$(ls -A "$DEST_DIR" 2>/dev/null)" ]]; then
        HAS_CONTENT=true
    fi

    dock_plist="$HOME/Library/Preferences/com.apple.dock.plist"

    # Check if currently in Dock (using robust grep check on XML)
    IS_IN_DOCK=false
    DEST_DIR_URL="${DEST_DIR// /%20}"
    
    # We dump to a temp variable to avoid running plutil multiple times
    CURR_DOCK_XML=$(plutil -convert xml1 "$dock_plist" -o -)
    
    # Improved check: look for "Windows Apps" label specifically in persistent-others
    # This avoids matches in other sections of the plist.
    if echo "$CURR_DOCK_XML" | sed -n '/<key>persistent-others<\/key>/,/<\/array>/p' | grep -q "<string>Windows Apps</string>" || \
       echo "$CURR_DOCK_XML" | sed -n '/<key>persistent-others<\/key>/,/<\/array>/p' | grep -Fq "$DEST_DIR" || \
       echo "$CURR_DOCK_XML" | sed -n '/<key>persistent-others<\/key>/,/<\/array>/p' | grep -Fq "$DEST_DIR_URL"; then
       IS_IN_DOCK=true
    fi

    # LOGIC: Ensure State Matches Content
    
    if [[ "$HAS_CONTENT" == "true" && "$IS_IN_DOCK" == "false" ]]; then
        log "Adding 'Windows Apps' to Dock (New Apps Detected)..."
        
        # Create a temporary file for the new Dock tile
        ITEM_PLIST=$(mktemp)
        cat <<EOF > "$ITEM_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>tile-data</key>
    <dict>
        <key>file-data</key>
        <dict>
            <key>_CFURLString</key>
            <string>$DEST_DIR</string>
            <key>_CFURLStringType</key>
            <integer>0</integer>
        </dict>
        <key>file-label</key>
        <string>Windows Apps</string>
        <key>file-type</key>
        <integer>2</integer>
    </dict>
    <key>tile-type</key>
    <string>directory-tile</string>
</dict>
</plist>
EOF
        
        # Insert at index 0
        /usr/libexec/PlistBuddy -c "Add :persistent-others:0 dict" "$dock_plist"
        /usr/libexec/PlistBuddy -c "Merge '$ITEM_PLIST' :persistent-others:0" "$dock_plist"
        
        if [[ $? -eq 0 ]]; then
            log "Restarting Dock to apply changes..."
            killall Dock
        else
            log "Error: Failed to modify Dock plist."
        fi
        rm "$ITEM_PLIST"

    elif [[ "$HAS_CONTENT" == "false" && "$IS_IN_DOCK" == "true" ]]; then
        log "Removing 'Windows Apps' from Dock (Folder Empty)..."
        
        # Remove Logic: Find and Delete
        # We iterate backwards to avoid index shifting problems
        COUNT=$(/usr/libexec/PlistBuddy -c "Print persistent-others" "$dock_plist" 2>/dev/null | grep -c "Dict")
        
        REMOVED=false
        
        # Check if count is integer
        if [[ "$COUNT" =~ ^[0-9]+$ ]]; then
            for ((i=COUNT-1; i>=0; i--)); do
                # Get Data
                VAL=$(/usr/libexec/PlistBuddy -c "Print persistent-others:$i:tile-data:file-data:_CFURLString" "$dock_plist" 2>/dev/null)
                LABEL=$(/usr/libexec/PlistBuddy -c "Print persistent-others:$i:tile-data:file-label" "$dock_plist" 2>/dev/null)
                
                # Check for match (Path or Label)
                # We interpret strict equality on Label to minimize collateral damage,
                # But allowing 'file://' prefix on path.
                
                IS_MATCH=false
                if [[ "$LABEL" == "Windows Apps" ]]; then
                    IS_MATCH=true
                elif [[ "$VAL" == *"$DEST_DIR"* || "$VAL" == *"$DEST_DIR_URL"* ]]; then
                    IS_MATCH=true
                fi

                if [[ "$IS_MATCH" == "true" ]]; then
                    log "Removing Dock Item at index $i (Label: $LABEL, Path: $VAL)"
                    /usr/libexec/PlistBuddy -c "Delete persistent-others:$i" "$dock_plist"
                    REMOVED=true
                fi
            done
            
            if [[ "$REMOVED" == "true" ]]; then
                 log "Restarting Dock to apply removal..."
                 killall Dock
            else
                 log "Warning: detected in Dock but failed to find item index to remove."
            fi
        fi
    fi
}

# ==============================================================================
# Main
# ==============================================================================

log "Agent started. Monitoring $SOURCE_ROOT"
ensure_dest_dir

FIRST_RUN=1
while true; do
    sync_apps
    SYNC_STATUS=$?
    
    if [[ $SYNC_STATUS -eq 1 || $FIRST_RUN -eq 1 ]]; then
        manage_dock
        FIRST_RUN=0
    fi
    
    sleep "$POLL_INTERVAL"
done
