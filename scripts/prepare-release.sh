#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/fetch-sparkle.sh
SPARKLE_DIR=".dependencies/Sparkle"
PUBLIC_KEY=$("$SPARKLE_DIR/bin/generate_keys" --account com.weread.drawer -p)
EXPECTED_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)
if [[ "$PUBLIC_KEY" != "$EXPECTED_KEY" ]]; then
    echo "更新签名密钥与 Resources/Info.plist 不一致，请恢复 com.weread.drawer 对应的钥匙串密钥。" >&2
    exit 1
fi

make clean
make build
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
ARCHIVE="WeReadDrawer-v${VERSION}-macOS.dmg"
mkdir -p build/release
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto build/WeReadDrawer.app "$STAGING/WeReadDrawer.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname WeReadDrawer -srcfolder "$STAGING" -format UDZO \
    "build/release/$ARCHIVE"
"$SPARKLE_DIR/bin/generate_appcast" --account com.weread.drawer \
    --download-url-prefix "https://github.com/Ljhhhhhh/weread-drawer-macos/releases/download/v${VERSION}/" \
    --maximum-deltas 0 build/release
SIGNATURE=$(/usr/bin/xmllint --xpath 'string(//enclosure/@*[local-name()="edSignature"])' build/release/appcast.xml)
"$SPARKLE_DIR/bin/sign_update" --account com.weread.drawer --verify "build/release/$ARCHIVE" "$SIGNATURE"
"$SPARKLE_DIR/bin/sign_update" --account com.weread.drawer --verify build/release/appcast.xml
(cd build/release && shasum -a 256 "$ARCHIVE" appcast.xml > SHA256SUMS)
echo "发布文件已生成：build/release（版本 v${VERSION}）"
