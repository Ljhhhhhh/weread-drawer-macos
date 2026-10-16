#!/usr/bin/env bash
set -e

APP_NAME="WeReadDrawer"
OUTPUT_DIR="build/${APP_NAME}.app"

echo "==> Building ${APP_NAME}..."
mkdir -p "${OUTPUT_DIR}/Contents/MacOS"
mkdir -p "${OUTPUT_DIR}/Contents/Resources"

swiftc -O Sources/main.swift \
    -o "${OUTPUT_DIR}/Contents/MacOS/${APP_NAME}" \
    -framework Cocoa \
    -framework WebKit \
    -framework Carbon \
    -framework SwiftUI

cp Resources/Info.plist "${OUTPUT_DIR}/Contents/Info.plist"
cp Resources/AppIcon.icns "${OUTPUT_DIR}/Contents/Resources/AppIcon.icns"
cp Resources/MenuBar-template.pdf "${OUTPUT_DIR}/Contents/Resources/MenuBar-template.pdf"
codesign --force --sign - "${OUTPUT_DIR}"

echo "==> Build complete: ${OUTPUT_DIR}"
