#!/bin/bash
# Build a distributable SousVide.app, a DMG (human download), a signed .zip +
# appcast.xml (Sparkle auto-update channel), and — with --publish — cut the
# GitHub release and push the appcast. Mirrors oxine's release.sh.
#
#   ./release.sh            build everything into dist/ + docs/appcast.xml
#   ./release.sh --publish  …then create the GitHub release + push the appcast
#
# Signed with the neutral self-signed "Oxine" identity (CN=Oxine) — the same
# author cert Oxine ships with, which the sous-vide daemon's client check
# accepts. Not a Developer ID, not notarized: the first download is quarantined
# (right-click → Open, or Privacy & Security → Open Anyway). Sparkle verifies
# every later update with the EdDSA key and installs it silently.
set -e
cd "$(dirname "$0")"

APP="SousVide.app"
DIST="dist"
REPO="alfaoz/sous-vide"
BIN="SousVide"
HELPER="com.sousvide.soushelper"
SIGN_ID="Oxine"
BUNDLE_ID="com.sousvide.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
TAG="v$VERSION"
DOWNLOAD_PREFIX="https://github.com/$REPO/releases/download/$TAG/"

PUBLISH=0
CRITICAL=0
for arg in "$@"; do
  [ "$arg" = "--publish" ] && PUBLISH=1
  [ "$arg" = "--critical" ] && CRITICAL=1   # mark this release mandatory (no Skip/Later)
done

SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
SPARKLE_FW=$(find .build/artifacts -path "*macos-arm64_x86_64/Sparkle.framework" -type d 2>/dev/null | head -1)
[ -n "$SPARKLE_FW" ] || { echo "✗ Sparkle.framework not found — run 'swift build' once." >&2; exit 1; }

if ! security find-identity -v -p codesigning | grep -q "\"$SIGN_ID\""; then
  echo "✗ '$SIGN_ID' is not a valid code-signing identity (the neutral release cert)." >&2
  exit 1
fi

echo "▸ building release ($(uname -m))…"
swift build -c release --product "$BIN"
swift build -c release --product "$HELPER"

echo "▸ assembling app bundle…"
rm -rf "$DIST"; mkdir -p "$DIST"
cp -R "$APP" "$DIST/$APP"
cp ".build/release/$BIN" "$DIST/$APP/Contents/MacOS/$BIN"
cp ".build/release/$HELPER" "$DIST/$APP/Contents/MacOS/$HELPER"
rm -rf "$DIST/$APP/Contents/_CodeSignature"

echo "▸ embedding Sparkle.framework…"
rm -rf "$DIST/$APP/Contents/Frameworks"; mkdir -p "$DIST/$APP/Contents/Frameworks"
cp -R "$SPARKLE_FW" "$DIST/$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$DIST/$APP/Contents/MacOS/$BIN" 2>/dev/null || true

echo "▸ signing with '$SIGN_ID'…"
codesign --force --sign "$SIGN_ID" --identifier "$HELPER" "$DIST/$APP/Contents/MacOS/$HELPER"
codesign --force --sign "$SIGN_ID" "$DIST/$APP/Contents/MacOS/$BIN"
codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" "$DIST/$APP"
codesign --verify --deep --strict "$DIST/$APP" && echo "  ✓ signature valid"

echo "▸ packaging Sparkle update (.zip) + appcast…"
UPDATES="$DIST/updates"; mkdir -p "$UPDATES" docs
ditto -c -k --keepParent "$DIST/$APP" "$UPDATES/SousVide-$VERSION.zip"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "https://github.com/$REPO" \
  -o docs/appcast.xml \
  "$UPDATES"
echo "  ✓ docs/appcast.xml ($VERSION)"

# Stamp this version's appcast item as a critical update (Install only, no Skip/Later).
if [ "$CRITICAL" = "1" ]; then
  APPCAST="docs/appcast.xml" TARGET_VERSION="$VERSION" python3 - <<'PY'
import os, re
path, ver = os.environ["APPCAST"], os.environ["TARGET_VERSION"]
xml = open(path).read()
def mark(item):
    if "sparkle:criticalUpdate" in item: return item
    if f"<sparkle:shortVersionString>{ver}</sparkle:shortVersionString>" not in item: return item
    return re.sub(r"(<sparkle:shortVersionString>.*?</sparkle:shortVersionString>)",
                  r"\1\n            <sparkle:criticalUpdate></sparkle:criticalUpdate>", item, count=1)
xml = re.sub(r"<item>.*?</item>", lambda m: mark(m.group(0)), xml, flags=re.S)
open(path, "w").write(xml)
print(f"  ✓ marked {ver} as a CRITICAL update")
PY
fi

echo "▸ building DMG…"
DMG="$DIST/SousVide-$VERSION.dmg"; VOL="sous-vide"; RW="$DIST/rw.dmg"
rm -f "$DMG" "$RW"
for v in "/Volumes/$VOL" "/Volumes/$VOL "*; do [ -e "$v" ] && hdiutil detach "$v" -force >/dev/null 2>&1; done
STAGE=$(mktemp -d)
cp -R "$DIST/$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"; cp branding/dmg-bg-black.png "$STAGE/.background/background.png"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
rm -rf "$STAGE"
MOUNT=$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*' | tail -1)
MVOL=$(basename "$MOUNT"); sleep 2
osascript <<APPLESCRIPT || echo "  (Finder styling skipped — DMG still installs fine)"
tell application "Finder"
  tell disk "$MVOL"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 740, 500}
    delay 1
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    try
      set background picture of theViewOptions to file ".background:background.png"
    end try
    set position of item "$APP" of container window to {140, 175}
    set position of item "Applications" of container window to {400, 175}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach "$MOUNT" >/dev/null 2>&1 || hdiutil detach "$MOUNT" -force >/dev/null 2>&1
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"
echo "✓ $DMG  ($(du -h "$DMG" | cut -f1))"

if [ "$PUBLISH" = "1" ]; then
  echo "▸ publishing release $TAG to $REPO…"
  git add docs/appcast.xml
  git commit -m "Release $TAG" >/dev/null 2>&1 || echo "  (appcast unchanged)"
  git push
  if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DMG" "$UPDATES/SousVide-$VERSION.zip" --clobber
  else
    gh release create "$TAG" "$DMG" "$UPDATES/SousVide-$VERSION.zip" \
      --title "sous-vide $VERSION" \
      --notes "First launch: open System Settings → Privacy & Security and click \"Open Anyway\" to allow sous-vide. Apple Silicon only."
  fi
  echo "✓ published $TAG"
fi
