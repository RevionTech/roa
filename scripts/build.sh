#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING_IDENTITY="${ROA_SIGNING_IDENTITY:--}"
sign_code() {
    if [[ "$SIGNING_IDENTITY" == - ]]; then
        /usr/bin/codesign --force --sign - "$@"
    else
        /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$@"
    fi
}
[[ "$(uname -s)" == Darwin ]] || { echo "ROA builds on macOS only." >&2; exit 1; }
/usr/bin/xcrun --find swift >/dev/null || { echo "Install Command Line Tools: xcode-select --install" >&2; exit 1; }
cd "$ROOT"
if [[ "${ROA_UNIVERSAL:-0}" == 1 ]]; then
    for arch in arm64 x86_64; do
        /usr/bin/xcrun swift build -c release --triple "$arch-apple-macosx13.0" --scratch-path ".build/release-$arch"
    done
    ARM_BIN="$(/usr/bin/xcrun swift build -c release --triple arm64-apple-macosx13.0 --scratch-path .build/release-arm64 --show-bin-path)"
    INTEL_BIN="$(/usr/bin/xcrun swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path .build/release-x86_64 --show-bin-path)"
    SPARKLE="$ROOT/.build/release-arm64/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    BIN="$ROOT/.build/universal"
    mkdir -p "$BIN"
    for product in roa-menubar roa roa-service; do
        /usr/bin/lipo -create "$ARM_BIN/$product" "$INTEL_BIN/$product" -output "$BIN/$product"
    done
else
    /usr/bin/xcrun swift build -c release
    BIN="$(/usr/bin/xcrun swift build -c release --show-bin-path)"
    SPARKLE="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi
STAGE="$ROOT/dist/ROA.app/Contents"
rm -rf "$ROOT/dist/ROA.app"
mkdir -p "$STAGE/MacOS" "$STAGE/Resources"
/usr/bin/install -m 755 "$BIN/roa-menubar" "$STAGE/MacOS/ROA"
/usr/bin/strip -S "$STAGE/MacOS/ROA"
/usr/bin/install -m 644 "$ROOT/Assets/symbol.pdf" "$STAGE/Resources/symbol.pdf"
/usr/bin/install -m 644 "$ROOT/Resources/Info.plist" "$STAGE/Info.plist"
/usr/bin/xcrun swift "$ROOT/tools/make-icon.swift" "$ROOT/Assets/symbol.pdf" "$ROOT/dist"
/usr/bin/install -m 755 "$BIN/roa" "$ROOT/dist/roa"
/usr/bin/strip -S "$ROOT/dist/roa"
sign_code --identifier net.reviontech.roa.cli "$ROOT/dist/roa"
/usr/bin/codesign --verify --strict "$ROOT/dist/roa"
/usr/bin/install -m 755 "$BIN/roa-service" "$ROOT/dist/roa-service"
/usr/bin/strip -S "$ROOT/dist/roa-service"
sign_code --identifier net.reviontech.roa.service "$ROOT/dist/roa-service"
/usr/bin/codesign --verify --strict "$ROOT/dist/roa-service"
mkdir -p "$STAGE/Helpers" "$STAGE/Frameworks"
/usr/bin/ditto "$SPARKLE" "$STAGE/Frameworks/Sparkle.framework"
python3 "$ROOT/tools/sign-framework.py" "$STAGE/Frameworks/Sparkle.framework" "$SIGNING_IDENTITY"
/usr/bin/install -m 755 "$ROOT/dist/roa" "$ROOT/dist/roa-service" "$STAGE/Helpers/"
/usr/bin/install -m 644 "$ROOT/Resources/service.plist" "$ROOT/Resources/login.plist" "$ROOT/Assets/Sparkle-LICENSE.txt" "$STAGE/Resources/"
sign_code "$ROOT/dist/ROA.app"
/usr/bin/codesign --verify --deep --strict "$ROOT/dist/ROA.app"
echo "Built: dist/ROA.app, dist/roa, dist/roa-service"
