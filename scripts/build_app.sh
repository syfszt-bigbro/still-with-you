#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
ROOT=${SCRIPT_DIR:h}
DIST="$ROOT/dist"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/Still With You.app"
CONTENTS="$APP/Contents"

swift build -c release --package-path "$ROOT"

if [[ "$DIST" != "$ROOT/dist" ]]; then
  print -u2 "Refusing unexpected output directory: $DIST"
  exit 1
fi
rm -rf "$DIST"
mkdir -p "$DIST"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/StillWithYou" "$CONTENTS/MacOS/StillWithYou"
cp "$ROOT/Config/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Sources/StillWithYouApp/Resources/AppIcon.png" "$CONTENTS/Resources/AppIcon.png"

for bundle in "$ROOT"/.build/release/StillWithYou_*.bundle; do
  [[ -d "$bundle" ]] || continue
  ditto "$bundle" "$CONTENTS/Resources/${bundle:t}"
done

xcrun swiftc -O "$ROOT/Helpers/CredentialVault.swift" \
  -o "$CONTENTS/Resources/credential-vault-v2"
chmod 700 "$CONTENTS/Resources/credential-vault-v2"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

ditto --noextattr "$APP" "$DIST/Still With You.app"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/Still-With-You-macOS.zip"

# Verify the exact archive users download, outside File Provider-managed folders
# that may attach Finder metadata to a copied .app after signing.
VERIFY="$WORK/verify"
mkdir -p "$VERIFY"
ditto -x -k "$DIST/Still-With-You-macOS.zip" "$VERIFY"
codesign --verify --deep --strict "$VERIFY/Still With You.app"
test -x "$VERIFY/Still With You.app/Contents/MacOS/StillWithYou"

print "$DIST/Still With You.app"
print "$DIST/Still-With-You-macOS.zip"
