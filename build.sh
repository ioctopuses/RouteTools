#!/usr/bin/env bash
#
# RouteBar 打包脚本（通用二进制：arm64 + x86_64）
# 依赖：Xcode 命令行工具（xcode-select --install）
# 用法：bash build.sh
#
set -euo pipefail

APP_NAME="RouteBar"
SRC_DIR="Sources/RouteBar"
BUILD_DIR=".build"
APP_BUNDLE="$APP_NAME.app"
MIN_MACOS="13.0"   # 最低支持 macOS 13（含 macOS 14 的 Intel / Apple Silicon）

# Swift 源文件
SWIFT_SOURCES=(
  "$SRC_DIR/RouteModel.swift"
  "$SRC_DIR/RouteStore.swift"
  "$SRC_DIR/RouteBarApp.swift"
)

# 交叉编译单个架构（含 Objective-C 桥接层）
build_arch() {
  local arch="$1"
  local triple="$arch-apple-macosx$MIN_MACOS"
  echo "==> 编译 $arch ($triple)"

  # Objective-C 桥接层：调用 Authorization Services（Swift 中该 API 不可用）
  clang -c -target "$triple" -I"$SRC_DIR" \
    -o "$BUILD_DIR/PrivilegedShim-$arch.o" \
    "$SRC_DIR/PrivilegedShim.m"

  swiftc -O -target "$triple" \
    -import-objc-header "$SRC_DIR/Bridging.h" \
    -framework Security \
    -o "$BUILD_DIR/$APP_NAME-$arch" \
    "${SWIFT_SOURCES[@]}" \
    "$BUILD_DIR/PrivilegedShim-$arch.o"
}

echo "==> 清理旧的构建产物"
rm -rf "$BUILD_DIR" "$APP_BUNDLE"
mkdir -p "$BUILD_DIR"

# 分别编译 arm64 与 x86_64
build_arch "arm64"    # Apple Silicon
build_arch "x86_64"   # Intel

echo "==> 合并通用二进制 (universal: arm64 + x86_64)"
lipo -create -output "$BUILD_DIR/$APP_NAME" \
  "$BUILD_DIR/$APP_NAME-arm64" \
  "$BUILD_DIR/$APP_NAME-x86_64"
lipo -info "$BUILD_DIR/$APP_NAME"

echo "==> 打包 .app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# 图标（若存在则复制）
if [ -f "AppIcon.icns" ]; then
  cp "AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "==> 自签名（ad-hoc）"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> 完成：$APP_BUNDLE"
echo "    架构：$(lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | sed 's/.*://')"
echo "    双击打开，或拖入 /Applications 常驻使用。"
echo "    若提示“无法验证开发者”，请执行："
echo "    xattr -dr com.apple.quarantine \"$APP_BUNDLE\""
