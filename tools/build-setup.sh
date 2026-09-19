#!/bin/bash
# 一键出安装包：发布 self-contained 产物 -> 收集 WiX 文件清单 -> 编 MSI + EXE 两种安装包
# 用法: bash tools/build-setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
Version="1.2.0"
SrcRoot="$(cygpath -w "$PWD")\\"
Out="out"

dotnet publish JiaHaoToolBox/JiaHaoToolBox.csproj -c Release -r win-x64 --self-contained true -o publish
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
