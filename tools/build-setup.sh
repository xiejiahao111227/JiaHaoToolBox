#!/bin/bash
# 一键出安装包：发布 self-contained 产物 -> 收集 WiX 文件清单 -> 编 MSI + EXE 两种安装包
# 用法: bash tools/build-setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
Version="1.5.0"
SrcRoot="$(cygpath -w "$PWD")\\"
Out="out"

dotnet publish JiaHaoToolBox/JiaHaoToolBox.csproj -c Release -r win-x64 --self-contained true -o publish

# adb / fastboot 不入库，构建前必须在 publish/platform-tools 下；漏了的话装出来的工具箱检测不到手机
if [ ! -f publish/platform-tools/adb.exe ]; then
    echo "缺少 publish/platform-tools，正在自动下载官方 platform-tools（bash tools/get-platform-tools.sh 可单独执行）"
    bash tools/get-platform-tools.sh
fi
[ -f publish/platform-tools/adb.exe ] || { echo "platform-tools 准备失败，中止打包" >&2; exit 1; }

powershell -NoProfile -ExecutionPolicy Bypass -File tools/harvest-publish.ps1

mkdir -p "$Out"
wix build setup/setup.wxs setup/files.wxs \
    -ext WixToolset.UI.wixext \
    -arch x64 \
    -d "SrcRoot=$SrcRoot" \
    -dcl mszip \
    -o "$Out/JiaHaoToolBox-Setup-$Version.msi"

# Inno Setup 装在每用户目录，ISCC.exe 不在 PATH 里
ISCC="$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe"
if [ -f "$ISCC" ]; then
    "$ISCC" setup/JiaHaoToolBox.iss
else
    echo "跳过 EXE 安装包：未找到 $ISCC"
fi

ls -la "$Out"
