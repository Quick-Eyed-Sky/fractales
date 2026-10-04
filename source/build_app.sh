#!/bin/zsh
# Builds "Fractales.app" next to this folder from the sources in it.
# Needs only Apple's command line tools (clang and swiftc), not the full Xcode.
# The Metal shaders are compiled by the app itself when it starts, so no Metal toolchain either.
#
#   cd fractales/source && ./build_app.sh

set -e
if ! command -v swiftc >/dev/null 2>&1; then
  echo "swiftc est introuvable. Installe d'abord les outils en ligne de commande d'Apple :"
  echo "    xcode-select --install"
  echo "puis relance ce script."
  exit 1
fi
HERE="${0:A:h}"
ROOT="${HERE:h}"
APP="$ROOT/Fractales.app"
BUILD="$HERE/.build"
TARGET="arm64-apple-macos14.0"

# One version number, defined once, in FractalModel.swift.
VERSION=$(grep -E 'static let version = ' "$HERE/FractalModel.swift" | sed -E 's/.*"([^"]+)".*/\1/')
echo "Construction de Fractales $VERSION ..."

rm -rf "$BUILD"; mkdir -p "$BUILD"
clang -O3 -std=c11 -Wall -target "$TARGET" -c "$HERE/FractalCore.c" -o "$BUILD/FractalCore.o"
swiftc -O -swift-version 5 -parse-as-library \
  -target "$TARGET" \
  -import-objc-header "$HERE/FractalCore.h" \
  "$HERE/FractalModel.swift" "$HERE/Renderer.swift" "$HERE/CanvasView.swift" "$HERE/FractalesApp.swift" \
  "$BUILD/FractalCore.o" \
  -o "$BUILD/Fractales"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/Fractales" "$APP/Contents/MacOS/Fractales"
cp "$HERE/Shaders.metal" "$APP/Contents/Resources/Shaders.metal"
# Texts in French and English: macOS shows the language of the Mac, English if it is neither.
for LANG_DIR in "$HERE"/*.lproj; do
  plutil -lint -s "$LANG_DIR"/*.strings
  cp -R "$LANG_DIR" "$APP/Contents/Resources/"
done
[ -f "$HERE/AppIcon.icns" ] && cp "$HERE/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Fractales</string>
  <key>CFBundleDisplayName</key><string>Fractales</string>
  <key>CFBundleIdentifier</key><string>com.jpm.fractales</string>
  <key>CFBundleExecutable</key><string>Fractales</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Copyright (C) 2026 Jean-Pascal (Quick-Eyed Sky). Logiciel libre sous licence MIT.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 && echo "Signée (ad hoc)."
echo "Terminé : $APP"
