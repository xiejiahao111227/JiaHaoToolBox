#!/bin/bash
# 生成 tools/nav-manifest.tsv：每行 "侧边栏项名称<TAB>输出前缀"，UTF-8 BOM 供 PowerShell 读取
set -eu
cd "$(dirname "$0")"
printf '\xef\xbb\xbf' > nav-manifest.tsv
add() { printf '%s\t%s\n' "$1" "$2" >> nav-manifest.tsv; }
add 主页 home
add 投屏 mirror
add 基本刷入 basic
add 可视刷写 fastboot
add 欧加线刷 ouga
add EDL刷写 edl
add 降级助手 downgrade
add 模块专区 mod
add 断点续传 resume
add 文件传输 filexfer
add 脱机修补 magisk
add 应用管理 appmgr
add 安卓通用 android
add Payload payload
add 备份助手 backup
add 下载专区 dl
add Rom专区 rom
add 关于 about
cat nav-manifest.tsv
