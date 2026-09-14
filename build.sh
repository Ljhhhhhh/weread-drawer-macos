#!/usr/bin/env bash
set -e

APP_NAME="WeReadDrawer"
OUTPUT_DIR="build/${APP_NAME}.app"

echo "==> Building ${APP_NAME}..."
mkdir -p "${OUTPUT_DIR}/Contents/MacOS"
mkdir -p "${OUTPUT_DIR}/Contents/Resources"

swiftc Sources/main.swift \
    -o "${OUTPUT_DIR}/Contents/MacOS/${APP_NAME}" \
    -framework Cocoa \
    -framework WebKit \
    -framework Carbon

cp Resources/Info.plist "${OUTPUT_DIR}/Contents/Info.plist"

echo "==> Build complete: ${OUTPUT_DIR}"
