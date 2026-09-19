#!/bin/bash
# 用法: ps-enc.sh <ps1 脚本> <前置赋值语句> <日志文件>
# PowerShell 5.1 在本机会随机在 AMSI 扫描脚本内容时段错误；-EncodedCommand 让被扫描
# 的文本变成 base64，实测能显著降低崩溃概率，脚本本身仍按 UTF-8 读取。
set -u
Script="$1"
Assign="$2"
Log="$3"
Tmp="$(mktemp -p "$(dirname "$Script")" enc-XXXXXX.ps1)"
{ printf '%s\n' "$Assign"; tail -n +2 "$Script"; } > "$Tmp"
for attempt in 1 2 3 4 5 6; do
    b64=$(iconv -f UTF-8 -t UTF-16LE "$Tmp" | base64 -w 0)
    powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand "$b64" > "$Log" 2>&1
    rc=$?
    # 段错误时 AMSI 崩溃只会留下几乎为空的日志
    if [ "$rc" -ne 0 ] || [ "$(wc -c < "$Log")" -lt 50 ] || grep -aq "AccessViolation" "$Log"; then
        echo "PS-CRASH attempt $attempt rc=$rc" >> "$Log"
        sleep 2
        continue
    fi
    rm -f "$Tmp"
    exit 0
done
rm -f "$Tmp"
exit 1
