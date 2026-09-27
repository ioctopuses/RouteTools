#!/usr/bin/env bash
#
# 创建本地代码签名证书「RouteBar Local Signing」（只需执行一次，10 年有效）
#
# 为什么要这张证书：
#   ad-hoc 签名（codesign --sign -）没有证书可锚定，其「指定要求」(designated
#   requirement) 只能退化成 cdhash H"…" —— 也就是二进制的哈希。每次重新编译
#   哈希都变，macOS 就把它当成一个**全新 App**：钥匙串授权、自动化授权、
#   隐私权限记录全部失效并重新弹窗，而失效的旧记录还会一直堆在设置列表里。
#   换成证书签名后，指定要求锚定在「identifier + 本机这张证书根」上，
#   重新编译后依然是「同一个 App」，授权可跨版本保持。
#
# 用法：
#   bash make_cert.sh
#
# 等价的手工做法（不想跑脚本时）：
#   钥匙串访问 → 证书助理 → 创建证书…
#     名称：RouteBar Local Signing   ← 必须与 build.sh 里的 SIGN_IDENTITY 一致
#     身份类型：自签名根证书
#     证书类型：代码签名
#     勾选「让我覆盖默认值」，有效期填 3650 天
#
set -euo pipefail

CERT_CN="RouteBar Local Signing"
CERT_ORG="RouteBar"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
VALID_DAYS=3650
P12_PASS="routebar"   # 仅用于本次导入的临时口令，导入后即丢弃

# 生成证书用它（支持 -addext 写扩展）；导出 p12 用它（产出 macOS 认的旧式加密）
OPENSSL_NEW="/opt/homebrew/bin/openssl"
[ -x "$OPENSSL_NEW" ] || OPENSSL_NEW="$(command -v openssl)"
OPENSSL_LEGACY="/usr/bin/openssl"

echo "=== RouteBar 本地签名证书 ==="

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_CN"; then
  echo "✅ 已存在签名身份「${CERT_CN}」，无需重复创建。"
  security find-identity -v -p codesigning | grep "$CERT_CN"
  exit 0
fi

WORK="$(mktemp -d)"
trap '/bin/rm -rf "$WORK"' EXIT

echo "==> 1/4 生成自签名证书（${VALID_DAYS} 天）"
"$OPENSSL_NEW" req -x509 -newkey rsa:2048 -sha256 -nodes \
  -days "$VALID_DAYS" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$CERT_CN/O=$CERT_ORG" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
echo "    CN=$CERT_CN  O=$CERT_ORG"

echo "==> 2/4 打包并导入钥匙串"
# 必须用旧式加密参数：OpenSSL 3 默认的 AES-256-CBC + PBKDF2 是 macOS
# security import 读不懂的新格式，会报 "Failed to import items"。
"$OPENSSL_LEGACY" pkcs12 -export \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" \
  -passout "pass:$P12_PASS" \
  -name "$CERT_CN"

# -T：把 codesign / security 写进密钥的访问控制列表，避免首次签名弹「允许访问」；
# -A：允许任意程序使用（本机自用，且证书不对外分发，取舍上选省事）。
security import "$WORK/identity.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASS" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -A \
  -f pkcs12 >/dev/null

echo "==> 3/4 把证书标记为受信任（Code Signing 策略）"
# 关键一步，漏了会误判成失败：自签名根证书导入后默认处于 CSSMERR_TP_NOT_TRUSTED 状态，
# `security find-identity -v`（只列"有效"身份）就**不会**显示它，虽然私钥和证书其实都在
# 钥匙串里、`codesign --sign` 也能用。加上一条 user 级信任记录后才算真正"有效"。
# 注：用 -k 指向登录钥匙串 = user 级信任（写入 ~/Library/Keychains），
#     不加 -d 就不需要管理员密码；`-r trustRoot` 表示"信任为本策略的根"。
security find-certificate -c "$CERT_CN" -p > "$WORK/trust.pem"
security add-trusted-cert -r trustRoot -p codeSign \
  -k "$KEYCHAIN" "$WORK/trust.pem"

echo "==> 4/4 验证"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_CN"; then
  security find-identity -v -p codesigning | grep "$CERT_CN"
  echo ""
  echo "✅ 完成。现在 bash build.sh 就会用这张证书签名。"
  echo ""
  echo "   ⚠️  别删钥匙串里那对「证书 + 私钥」——删掉 = 永久换了个身份，"
  echo "      会立刻回到「每次重新编译都要重新授权」的状态。"
  echo "       建议导出一次 .p12 当备份：钥匙串访问 → 我的证书 → 导出项目。"
else
  echo "❌ 未能在钥匙串中列出该身份，请改用钥匙串访问手工创建（见本脚本头部注释）。" >&2
  exit 1
fi
