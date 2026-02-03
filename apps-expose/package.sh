#!/bin/bash

# package.sh
# Builds the Parallels Windows Apps Exposure Agent .pkg installer

PROJECT_DIR=$(pwd)
BUILD_DIR="$PROJECT_DIR/build"
ROOT_DIR="$BUILD_DIR/root"
SCRIPTS_DIR="$BUILD_DIR/scripts"

IDENTIFIER="com.company.parallels-apps-expose-service"
VERSION="1.0"
PKG_NAME="ParallelsAppsExposeService.pkg"

# Cleanup
echo "Cleaning up previous build..."
rm -rf "$BUILD_DIR"

# Create Directory Structure
echo "Creating directory structure..."
mkdir -p "$ROOT_DIR/usr/local/bin"
mkdir -p "$ROOT_DIR/Library/LaunchAgents"
mkdir -p "$SCRIPTS_DIR"

# Copy Files
echo "Copying files..."

# 1. Agent Script
if [[ -f "$PROJECT_DIR/parallels_apps_expose_service.sh" ]]; then
    cp "$PROJECT_DIR/parallels_apps_expose_service.sh" "$ROOT_DIR/usr/local/bin/"
    chmod 755 "$ROOT_DIR/usr/local/bin/parallels_apps_expose_service.sh"
else
    echo "Error: parallels_apps_expose_service.sh not found."
    exit 1
fi

# 2. LaunchAgent Plist
if [[ -f "$PROJECT_DIR/com.company.parallels-apps-expose-service.plist" ]]; then
    cp "$PROJECT_DIR/com.company.parallels-apps-expose-service.plist" "$ROOT_DIR/Library/LaunchAgents/"
    chmod 644 "$ROOT_DIR/Library/LaunchAgents/com.company.parallels-apps-expose-service.plist"
else
    echo "Error: com.company.parallels-apps-expose-service.plist not found."
    exit 1
fi

# 3. Create postinstall script to load the LaunchAgent
# Note: Since this is often installed via MDM/Jamf, loading for the *current* user at install time checks console user.
# But standard practice for LaunchAgents is they load on next login.
# However, we can try to boostrap it for the current logged in user.

POSTINSTALL="$SCRIPTS_DIR/postinstall"
cat <<EOF > "$POSTINSTALL"
#!/bin/bash
# postinstall script

# Correct permissions just in case
chown root:wheel /usr/local/bin/parallels_apps_expose_service.sh
chmod 755 /usr/local/bin/parallels_apps_expose_service.sh
chown root:wheel /Library/LaunchAgents/com.company.parallels-apps-expose-service.plist
chmod 644 /Library/LaunchAgents/com.company.parallels-apps-expose-service.plist

# Load Agent for the currently logged in user (if any)
CURRENT_USER=\$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print \$3 }')
USER_ID=\$(id -u "\$CURRENT_USER")

if [[ -n "\$CURRENT_USER" ]]; then
    echo "Loading agent for user: \$CURRENT_USER (\$USER_ID)"
    launchctl bootstrap gui/\$USER_ID /Library/LaunchAgents/com.company.parallels-apps-expose-service.plist
fi

exit 0
EOF
chmod +x "$POSTINSTALL"

# Build Package
echo "Building package..."

# Note: Add --sign "Developer ID Installer: ..." to parameters if you have a certificate.
pkgbuild --root "$ROOT_DIR" \
         --identifier "$IDENTIFIER" \
         --version "$VERSION" \
         --scripts "$SCRIPTS_DIR" \
         --install-location "/" \
         "$BUILD_DIR/$PKG_NAME"

echo "Build complete: $BUILD_DIR/$PKG_NAME"
