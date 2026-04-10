#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/mdair.app"
EXT_BUNDLE="$APP_BUNDLE/Contents/PlugIns/QLMarkdownPreview.appex"

echo "=== mdair Build ==="

rm -rf "$APP_BUNDLE"

# --- 1. Build App ---
echo "[1/4] Building mdair.app..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$PROJECT_ROOT/AppInfo.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_ROOT/resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
echo -n "APPLMDAR" > "$APP_BUNDLE/Contents/PkgInfo"

clang \
    -arch arm64 -arch x86_64 \
    -mmacosx-version-min=13.0 \
    -framework Cocoa \
    -framework WebKit \
    -framework Foundation \
    -framework QuickLook \
    -framework CoreServices \
    -fobjc-arc \
    -w \
    -o "$APP_BUNDLE/Contents/MacOS/mdair" \
    "$PROJECT_ROOT/src/AppMain.m" \
    "$PROJECT_ROOT/src/GeneratePreview.m"

echo "  ✓ mdair.app"

# --- 2. Build QuickLook Preview Extension ---
echo "[2/4] Building QLMarkdownPreview.appex..."
mkdir -p "$EXT_BUNDLE/Contents/MacOS"

cp "$PROJECT_ROOT/ExtInfo.plist" "$EXT_BUNDLE/Contents/Info.plist"

# Compile Swift extension as appex executable with NSExtensionMain entry point
swiftc \
    -target arm64-apple-macosx13.0 \
    -module-name QLMarkdownPreview \
    -o "$EXT_BUNDLE/Contents/MacOS/QLMarkdownPreview" \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -Xlinker -rpath -Xlinker @executable_path/../../../../Frameworks \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -import-objc-header /dev/null \
    "$PROJECT_ROOT/src/PreviewExtension.swift" \
    2>&1

echo "  ✓ QLMarkdownPreview.appex"

# --- 3. Code Sign ---
echo "[3/4] Code signing..."
codesign --force --sign - --entitlements "$PROJECT_ROOT/ExtEntitlements.plist" "$EXT_BUNDLE" 2>&1
codesign --force --sign - "$APP_BUNDLE" 2>&1
echo "  ✓ Signed (ad-hoc)"

# --- 4. Verify ---
echo "[4/4] Verifying..."
FAIL=0
[ -f "$APP_BUNDLE/Contents/MacOS/mdair" ] || { echo "  ✗ App binary missing"; FAIL=1; }
[ -f "$EXT_BUNDLE/Contents/MacOS/QLMarkdownPreview" ] || { echo "  ✗ Extension binary missing"; FAIL=1; }
[ -f "$EXT_BUNDLE/Contents/Info.plist" ] || { echo "  ✗ Extension Info.plist missing"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then
    echo "  ✓ All verified"
else
    echo "  ✗ Verification failed!"
    exit 1
fi

echo ""
echo "=== Build complete ==="
echo "  $APP_BUNDLE"
echo "  └── Contents/PlugIns/QLMarkdownPreview.appex"
