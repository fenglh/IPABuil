#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SCHEME="IPABuild"
CONFIG="Release"
DERIVED_DATA="$ROOT_DIR/build"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIG"
APP_NAME="IPABuild.app"
APP_PATH="$PRODUCTS_DIR/$APP_NAME"
STAGE_DIR="$ROOT_DIR/dist/DMGStage"
DMG_OUTPUT="$ROOT_DIR/dist/certificate-manager.dmg"
VOLUME_NAME="证书管理"

printf "\n==> Building %s (%s)\n" "$SCHEME" "$CONFIG"
xcodebuild \
  -workspace "$ROOT_DIR/IPABuild.xcworkspace" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" \
  clean build

if [ ! -d "$APP_PATH" ]; then
  echo "错误：未找到构建产物 $APP_PATH" >&2
  exit 1
fi

printf "\n==> 准备 DMG 内容\n"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
rm -f "$DMG_OUTPUT"

cp -R "$APP_PATH" "$STAGE_DIR/$VOLUME_NAME.app"

printf "\n==> 创建 DMG：%s\n" "$DMG_OUTPUT"
mkdir -p "$(dirname "$DMG_OUTPUT")"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov -format UDZO "$DMG_OUTPUT"

printf "\n✅ 生成完成：%s\n" "$DMG_OUTPUT"
