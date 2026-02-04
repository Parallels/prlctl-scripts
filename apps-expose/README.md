# Parallels Windows Apps Exposure Service

A macOS background service that automatically monitors and exposes Windows applications from a Parallels Desktop VM to the macOS Dock.

## Detect, Expose, Dock.

This solution solves the problem of making user aware of new non default Windows applications in users posession (e.g. when setup of apps is conducted by device management solutions). It continuously monitors the Parallels VM application folder and mirrors eligible apps to a `Windows Apps` folder visible in the macOS Dock.

![demo](https://media2.giphy.com/media/v1.Y2lkPTc5MGI3NjExM3l5M2RpdHI4Y25hMWd2cTVjaGF0dml2NTg3ajYzOXNwMXQxdWhtYiZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/YqiQakOtpYKMRaAtXq/giphy.gif)

## Features

- **Automated Discovery**: Detects new `.app` bundles added by Windows managment solution (e.g. SCCM, Intune, etc.) or installed manually in the VM.
- **Immediate Exposure**: Creates symbolic links in `~/Applications (Parallels)/Windows Apps` instantly.
- **Cleanup**: Removes broken links if the source app is uninstalled.
- **Dock Integration**: Automatically adds the `Windows Apps` folder to the Dock (next to Downloads). It is smart enough to handle user removals and avoid duplicates.
- **Zero Config**: Works out of the box for standard Parallels setups.
- **Enterprise Ready**: Deploys as a standard macOS Package (`.pkg`) via Jamf/MDM.

## Installation

### Manual Installation
1. Run the installer package `ParallelsAppsExposeService.pkg`.
2. The service will start automatically (or upon next login).

### Deploying via Jamf
 Upload `ParallelsAppsExposeService.pkg` to Jamf Pro and deploy to target computers. The package includes a `postinstall` script that will attempt to load the agent for the current user immediately.

To build the package:
```bash
./package.sh
```
Artifact will be created at `build/ParallelsAppsExposeService.pkg`.

## MDM Configuration (Preventing Notifications)

When the service is installed, macOS will show a "Background Items Added" notification. To suppress this notification in a managed environment, you must deploy a Configuration Profile.

### Service Management Payload
Create a Configuration Profile with the **Service Management** payload (Managed Login Items).

- **Payload Scope**: System
- **Payload Type**: Service Management (`com.apple.servicemanagement`)

Add a new **Rule** with the following settings:
- **Rule Type**: `LabelPrefix`
- **Rule Value**: `com.company.parallels-apps-expose-service`
- **Comment**: Parallels Apps Expose Service

> [!NOTE]
> We use `LabelPrefix` because it targets the LaunchAgent's label in the plist. This effectively manages the service and suppresses notifications even if the underlying script is unsigned.

This tells macOS that the background service with this label prefix is managed, suppressing the user notification.

## Configuration

The agent is configured via environment variables at the top of `/usr/local/bin/parallels_apps_expose_service.sh`.
Default exclusions include:
- Calculator
- Camera
- Character Map
- Click to Do (preview)
- Clock
- Command Prompt
- Copilot
- Defragment and Optimize Drives
- Dev Home
- Disk Cleanup
- Feedback Hub
- File Explorer
- Game Bar
- Get Help
- Get Started
- Live captions
- Magnifier
- Media Player
- Microsoft 365 (Office)
- Microsoft Clipchamp
- Microsoft Edge
- Microsoft News
- Microsoft Store
- Microsoft Teams
- Microsoft To Do
- Narrator
- Notepad
- ODBC Data Sources (32-bit)
- On-Screen Keyboard
- Outlook
- Paint
- Phone Link
- Photos
- Quick Assist
- Recovery Drive
- Registry Editor
- Remote Desktop Connection
- Resource Monitor
- Settings
- Snipping Tool
- Solitaire & Casual Games
- Sound Recorder
- Steps Recorder
- Sticky Notes
- System Configuration
- System Information
- Task Manager
- Terminal
- Voice access
- Weather
- Windows Backup
- Windows Media Player Legacy
- Windows PowerShell
- Windows Security

To modify exclusions, edit the `EXCLUSIONS` variable in the script.

## Uninstalling

Run the provided uninstall script:
```bash
sudo ./uninstall.sh
```
Or manually:
1. `launchctl bootout gui/$(id -u) /Library/LaunchAgents/com.company.parallels-apps-expose-service.plist`
2. `rm /usr/local/bin/parallels_apps_expose_service.sh`
3. `rm /Library/LaunchAgents/com.company.parallels-apps-expose-service.plist`

## Logs

Logs are written to:
`~/Library/Logs/ParallelsAppsExposeService/service.log`

## Known issues

Non classic applications (e.g., packaged as MSIX) are not detected and exposed right away. The VM restart, App start or resetting the setting "Share Windows Applications with Mac" can enforce their detection. This might be addressed in Parallels Desktop updates.
