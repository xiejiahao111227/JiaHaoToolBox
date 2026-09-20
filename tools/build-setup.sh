#!/bin/bash
# 一键出安装包：发布 self-contained 产物 -> 收集 WiX 文件清单 -> 编 MSI + EXE 两种安装包
# 用法: bash tools/build-setup.sh
set -euo pipefail
cd "$(dirname "$0")/.."
Version="1.6.1"
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

# 许可页 RTF 里的版本号必须跟着安装包一起走：上一次就是只改了生成脚本没重跑，
# 结果 V1.6 的安装包许可页上还写着「版本 1.2.0（测试版 V1.2）」。
# 用 Node 而不是 PowerShell：本机 PowerShell 5.1 跑 tools/make-license-rtf.ps1 会在 AMSI 里段错误。
if command -v node >/dev/null 2>&1; then
    node tools/make-license-rtf.mjs
else
    echo "警告：PATH 里没有 node，setup/license.rtf 未重新生成，许可页版本可能与安装包不一致" >&2
fi
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
