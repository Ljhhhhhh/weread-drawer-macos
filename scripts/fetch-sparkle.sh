#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=2.10.0
SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
DEST=".dependencies/Sparkle"
if [[ -f "$DEST/.version" && "$(cat "$DEST/.version")" == "$VERSION" ]]; then
    exit 0
fi

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
curl --fail --location --retry 3 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" \
    -o "$TEMP_DIR/Sparkle.tar.xz"
printf '%s  %s\n' "$SHA256" "$TEMP_DIR/Sparkle.tar.xz" | shasum -a 256 -c -
tar -xf "$TEMP_DIR/Sparkle.tar.xz" -C "$TEMP_DIR"
mkdir -p .dependencies
rm -rf "$DEST"
mkdir -p "$DEST"
ditto "$TEMP_DIR/Sparkle.framework" "$DEST/Sparkle.framework"
ditto "$TEMP_DIR/bin" "$DEST/bin"
cp "$TEMP_DIR/LICENSE" "$DEST/LICENSE"
printf '%s\n' "$VERSION" > "$DEST/.version"
