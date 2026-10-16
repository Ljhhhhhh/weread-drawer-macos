#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

./scripts/fetch-sparkle.sh
SPARKLE_DIR=".dependencies/Sparkle"

APP_NAME="WeReadDrawer"
OUTPUT_DIR="build/${APP_NAME}.app"

echo "==> Building ${APP_NAME}..."
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}/Contents/MacOS"
mkdir -p "${OUTPUT_DIR}/Contents/Resources"
mkdir -p "${OUTPUT_DIR}/Contents/Frameworks"

for ARCH in arm64 x86_64; do
    swiftc -O Sources/main.swift \
        -target "${ARCH}-apple-macos14.0" \
        -o "build/${APP_NAME}-${ARCH}" \
        -framework Cocoa -framework WebKit -framework Carbon -framework SwiftUI \
        -F "${SPARKLE_DIR}" -framework Sparkle \
        -Xlinker -rpath -Xlinker @executable_path/../Frameworks
done
lipo -create "build/${APP_NAME}-arm64" "build/${APP_NAME}-x86_64" \
    -output "${OUTPUT_DIR}/Contents/MacOS/${APP_NAME}"
ditto "${SPARKLE_DIR}/Sparkle.framework" "${OUTPUT_DIR}/Contents/Frameworks/Sparkle.framework"
cp "${SPARKLE_DIR}/LICENSE" "${OUTPUT_DIR}/Contents/Resources/Sparkle-LICENSE.txt"

cp Resources/Info.plist "${OUTPUT_DIR}/Contents/Info.plist"
cp Resources/AppIcon.icns "${OUTPUT_DIR}/Contents/Resources/AppIcon.icns"
cp Resources/MenuBar-template.pdf "${OUTPUT_DIR}/Contents/Resources/MenuBar-template.pdf"
codesign --force --sign - "${OUTPUT_DIR}"
codesign --verify --deep --strict "${OUTPUT_DIR}"

echo "==> Build complete: ${OUTPUT_DIR}"
