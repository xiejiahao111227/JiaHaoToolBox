#!/bin/bash
# 用法: ps-enc.sh <ps1 脚本> <前置赋值语句> <日志文件>
# PowerShell 5.1 在本机会随机在 AMSI 扫描脚本内容时段错误（rc=139），所以每次都要带重试。
# 两种投递方式各有翻车的时候：
#   -File            需要临时文件带 UTF-8 BOM，否则 PowerShell 5.1 按本地 ANSI 码页解析，
#                    脚本里的中文（日志文案、按文字定位的导航标题）会全成乱码；
#   -EncodedCommand  被扫描的文本变成 base64，但 CreateProcess 命令行上限 32767 字符，
#                    脚本一长就 Argument list too long，而且实测它自己也会连续段错误。
# 所以两种模式轮流试，而不是认准一种反复重试。
set -u
Script="$1"
Assign="$2"
Log="$3"
Tmp="$(mktemp -p "$(dirname "$Script")" enc-XXXXXX.ps1)"
{ printf '%s\n' "$Assign"; tail -n +2 "$Script"; } > "$Tmp.body"
printf '\xEF\xBB\xBF' > "$Tmp"
cat "$Tmp.body" >> "$Tmp"
rm -f "$Tmp.body"
WinTmp="$(cygpath -w "$Tmp")"
# enc 模式必须喂无 BOM 的字节：-File 会自己吃掉 BOM，-EncodedCommand 不会，
# 那三个字节解出来成了零宽不换行空格，第一行赋值语句就变成一条不存在的命令（$Exe 直接空掉）。
B64="$(tail -c +4 "$Tmp" | iconv -f UTF-8 -t UTF-16LE | base64 -w 0)"

for attempt in 1 2 3 4 5 6; do
    if [ $((attempt % 2)) -eq 1 ]; then
        Mode="file"
        powershell -NoProfile -ExecutionPolicy Bypass -File "$WinTmp" > "$Log" 2>&1
    else
        Mode="enc"
        if [ "${#B64}" -gt 30000 ]; then
            echo "跳过 enc 模式：base64 长度 ${#B64} 超过命令行上限" >> "$Log"
            continue
        fi
        powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand "$B64" > "$Log" 2>&1
    fi
    rc=$?
    # 段错误时 AMSI 崩溃只会留下几乎为空的日志（阈值压到 8 字节，别把本来就只印一行的脚本误判成崩溃）
    if [ "$rc" -ne 0 ] || [ "$(wc -c < "$Log")" -lt 8 ] || grep -aq "AccessViolation" "$Log"; then
        echo "PS-CRASH mode=$Mode attempt $attempt rc=$rc" >> "$Log"
        sleep 2
        continue
    fi
    rm -f "$Tmp"
    exit 0
done
rm -f "$Tmp"
exit 1
