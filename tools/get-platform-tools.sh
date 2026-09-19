#!/bin/bash
# 下载并解压 Google 官方 platform-tools（adb / fastboot）到 publish/platform-tools。
# platform-tools 是 Google 的 Apache-2.0 二进制工具集，不入库，构建安装包前必须先跑这个脚本。
# 用法: bash tools/get-platform-tools.sh [目标目录...]
set -euo pipefail
cd "$(dirname "$0")/.."

URL="https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "下载 $URL"
curl -fL --retry 3 -o "$TMP/platform-tools.zip" "$URL"
sha256sum "$TMP/platform-tools.zip"
unzip -q "$TMP/platform-tools.zip" -d "$TMP"
[ -x "$TMP/platform-tools/adb.exe" ] || { echo "解压后未找到 adb.exe" >&2; exit 1; }

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then targets=("publish/platform-tools"); fi
for t in "${targets[@]}"; do
    mkdir -p "$(dirname "$t")"
    rm -rf "$t"
    cp -r "$TMP/platform-tools" "$t"
    echo "已写入 $t"
done
