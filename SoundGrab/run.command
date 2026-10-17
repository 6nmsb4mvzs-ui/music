#!/bin/bash
# Double-click this file to build and install SoundGrab.app
set -e
cd "$(dirname "$0")"

APP_NAME="SoundGrab"
APP_DIR="$HOME/Applications/$APP_NAME.app"

# Xcode CLI tools
if ! xcode-select -p &>/dev/null; then
    echo "Installing Xcode Command Line Tools (one-time)..."
    xcode-select --install
    echo "Re-run this after the install finishes."
    read -n1 -rsp "Press any key to close..."
    exit 0
fi

# Homebrew
if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
fi

# Dependencies
for dep in yt-dlp ffmpeg; do
    if ! command -v "$dep" &>/dev/null; then
        echo "Installing $dep..."
        brew install "$dep"
    fi
done

# Build
echo "Building $APP_NAME..."
swift build -c release --quiet 2>&1

if [ $? -ne 0 ]; then
    echo ""
    echo "Build failed. Retrying with verbose output..."
    swift build -c release
    read -n1 -rsp "Press any key to close..."
    exit 1
fi

# Create .app bundle
echo "Creating $APP_NAME.app..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp .build/release/$APP_NAME "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>SoundGrab</string>
    <key>CFBundleDisplayName</key>
    <string>SoundGrab</string>
    <key>CFBundleIdentifier</key>
    <string>com.soundgrab.app</string>
    <key>CFBundleVersion</key>
    <string>2.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.1.0</string>
    <key>CFBundleExecutable</key>
    <string>SoundGrab</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>SoundGrab needs access to Apple Music to import downloaded tracks.</string>
</dict>
</plist>
PLIST

# Update Spotlight index
/usr/bin/mdimport "$APP_DIR" 2>/dev/null || true

echo ""
echo "Installed to ~/Applications/$APP_NAME.app"
echo "You can now open SoundGrab from Spotlight (Cmd+Space → SoundGrab)"
echo ""
echo "Launching..."
open "$APP_DIR"

# Close this terminal window
osascript -e 'tell application "Terminal" to close front window' 2>/dev/null &
exit 0
