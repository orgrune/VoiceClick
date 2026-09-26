#!/bin/zsh
# Builds VoiceClick.app into ./build. Requires Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"
APP=VoiceClick
CONTENTS="build/$APP.app/Contents"
rm -rf "build/$APP.app"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
swiftc -O Sources/*.swift -o "$CONTENTS/MacOS/$APP" \
  -framework AppKit -framework SwiftUI -framework WebKit -framework Speech -framework AVFoundation
cp Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"
codesign --force --sign - "build/$APP.app"
echo "Built build/$APP.app"
