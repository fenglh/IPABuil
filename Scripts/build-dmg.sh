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
VOLUME_NAME="证书管理"
INFO_PLIST="$ROOT_DIR/IPABuild/Info.plist"

read_version_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST" 2>/dev/null || true
}

ensure_build_number() {
  local current next
  current=$(read_version_value "CFBundleVersion")
  if [[ "$current" =~ ^[0-9]+$ ]]; then
    next=$((current + 1))
  else
    next=1
  fi
  if /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next" "$INFO_PLIST" >/dev/null 2>&1; then
    :
  else
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $next" "$INFO_PLIST"
  fi
  echo "$next"
}

printf "==> 更新版本信息\n"
VERSION=$(read_version_value "CFBundleShortVersionString")
if [[ -z "$VERSION" ]]; then
  echo "错误：Info.plist 中缺少 CFBundleShortVersionString" >&2
  exit 1
fi
BUILD_NUMBER=$(ensure_build_number)
DMG_BASENAME="certificate-manager-v${VERSION}-build${BUILD_NUMBER}.dmg"
DMG_OUTPUT="$ROOT_DIR/dist/$DMG_BASENAME"

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
