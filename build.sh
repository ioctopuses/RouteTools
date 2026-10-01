#!/usr/bin/env bash
#
# RouteBar 打包脚本（通用二进制：arm64 + x86_64）
#
# 依赖：Xcode 命令行工具（xcode-select --install）
# 用法：bash build.sh
#
# 签名策略（借鉴 ApexBar）：优先用**稳定签名身份**而非 ad-hoc。
#   ad-hoc 签名的「指定要求」会退化成 cdhash H"…"，每次重新编译哈希都变，
#   系统把它当成一个全新 App —— 权限记录失效、反复重新弹窗，旧记录还清不掉。
#   证书签名则锚定 identifier + 证书根，重新编译后依然是"同一个 App"。
#   证书的创建方法见 README「签名与权限」一节。
#
set -euo pipefail

APP_NAME="RouteBar"
SRC_ROOT="Sources/RouteBar"
BUILD_DIR=".build"
APP_BUNDLE="$APP_NAME.app"
MIN_MACOS="13.0"
SIGN_IDENTITY="RouteBar Local Signing"
ENTITLEMENTS="RouteTools.entitlements"

echo "==> 清理旧的构建产物"
rm -rf "$BUILD_DIR" "$APP_BUNDLE"
mkdir -p "$BUILD_DIR"

# 自动发现源文件：早先是手写清单，新增文件忘了登记就会编不过，
# 而报错会落在**别的**文件里（cannot find 'X' in scope），排查方向容易被带偏。
SWIFT_SOURCES=()
while IFS= read -r f; do SWIFT_SOURCES+=("$f"); done \
  < <(/usr/bin/find "$SRC_ROOT" -name '*.swift' | /usr/bin/sort)

OBJC_SOURCES=()
while IFS= read -r f; do OBJC_SOURCES+=("$f"); done \
  < <(/usr/bin/find "$SRC_ROOT" -name '*.m' | /usr/bin/sort)

MACOS_SDK="$(xcrun --show-sdk-path)"
echo "    Swift: ${#SWIFT_SOURCES[@]} 个，Objective-C: ${#OBJC_SOURCES[@]} 个"
echo "    SDK: $MACOS_SDK"

# 交叉编译单个架构（含 Objective-C 桥接层）
build_arch() {
  local arch="$1"
  local triple="$arch-apple-macosx$MIN_MACOS"
  echo "==> 编译 $arch ($triple)"

  # Objective-C 桥接层：调用 Authorization Services（Swift 中该 API 被标记为不可用）
  # 逐个 .m 编译成 .o —— clang -c 多文件时无法用 -o 指定单一输出，所以分开编。
  local OBJ_ARGS=()
  local m
  for m in "${OBJC_SOURCES[@]}"; do
    local obj="$BUILD_DIR/$(basename "${m%.m}")-$arch.o"
    clang -c -target "$triple" -isysroot "$MACOS_SDK" -I"$SRC_ROOT" \
      -o "$obj" "$m"
    OBJ_ARGS+=("$obj")
  done

  # -disable-sandbox：禁用编译器为「宏插件进程」创建的 sandbox-exec 隔离。
  # 受限环境（容器 / 嵌套沙箱）下无法执行 sandbox_apply，会导致
  # swift-plugin-server 启动失败、报 "produced malformed response"，
  # 进而使 @State 等 SwiftUI 宏无法展开、整个编译失败。
  local LINK_INPUTS=("${SWIFT_SOURCES[@]}")
  if [ "${#OBJ_ARGS[@]}" -gt 0 ]; then
    LINK_INPUTS+=("${OBJ_ARGS[@]}")
  fi

  swiftc -O -target "$triple" -sdk "$MACOS_SDK" \
    -disable-sandbox \
    -import-objc-header "$SRC_ROOT/Bridging.h" \
    -framework AppKit -framework SwiftUI -framework Security \
    -o "$BUILD_DIR/$APP_NAME-$arch" \
    "${LINK_INPUTS[@]}"
}

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
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# 图标（若存在则复制）—— 必须在签名之前放好
if [ -f "AppIcon.icns" ]; then
  cp "AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# 菜单栏模板图标（@1x / @2x 两个分辨率）。
# `NSImage(named: "MenuBarIcon")` 会按屏幕缩放自动挑对应那张，只放 @1x
# 在 Retina 上会糊。同样必须在签名之前放入。
for icon in "MenuBarIcon.png" "MenuBarIcon@2x.png"; do
  if [ -f "Resources/${icon}" ]; then
    cp "Resources/${icon}" "$APP_BUNDLE/Contents/Resources/${icon}"
    echo "    已放入 ${icon}"
  else
    echo "    ⚠️  未找到 Resources/${icon}，菜单栏图标会回退到系统符号"
  fi
done

# 自动更新的替换助手脚本 —— 同样必须在签名之前放好。
# 签名会对 Contents/Resources 一并做资源封套校验，事后补进去的文件会让签名失效，
# 而更新恰恰要校验签名/结构，等于自断更新链路。
if [ -f "Resources/update-helper.sh" ]; then
  cp "Resources/update-helper.sh" "$APP_BUNDLE/Contents/Resources/update-helper.sh"
  chmod +x "$APP_BUNDLE/Contents/Resources/update-helper.sh"
  echo "    已放入 update-helper.sh"
else
  echo "    ⚠️  未找到 Resources/update-helper.sh，自动更新将不可用"
fi

echo "==> 签名"
# 注意：有 entitlements 文件但漏传 --entitlements 时，codesign 照样成功，
# 产物里却是空的（形同不存在）—— 所以这里必须显式带上。
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  codesign --force --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"
  echo "    ✅ 已用「${SIGN_IDENTITY}」签名（重新编译仍是同一个 App，权限可跨版本保持）"
else
  echo "    ⚠️  未找到签名身份「${SIGN_IDENTITY}」，回退到 ad-hoc 签名"
  echo "        注意：ad-hoc 会让权限记录每次重新编译都失效、反复弹窗。"
  echo "        建证书方法见 README「签名与权限」一节。"
  codesign --force --sign - \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"
fi

echo "==> 验证"
find "$APP_BUNDLE" -type f
codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier|Signature|Format" || true

echo ""
echo "==> 完成：$APP_BUNDLE"
echo "    架构：$(lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | sed 's/.*: //')"
echo "    双击打开，或运行 bash install.command 装到 /Applications。"
echo "    若提示“无法验证开发者”：xattr -dr com.apple.quarantine \"$APP_BUNDLE\""
