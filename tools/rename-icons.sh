#!/bin/bash
# 把 images/ 下所有中文命名图标改为 ASCII 名，并同步更新源码引用。
# 原因：MSBuild 将非 ASCII 资源名以小写百分号编码写入 .g.resources 键，
# WPF 运行时按大写编码查找，键不匹配 -> 图标全部空白。
set -u
cd "$(dirname "$0")/.." || exit 1
PROJ=JiaHaoToolBox
MAP=tools/icon-rename-map.txt
IMG=$PROJ/images

# 1) 覆盖率检查：磁盘上的非 ASCII 文件名必须全部在映射表中
missing=0
while IFS= read -r f; do
  grep -qP "^$f\t" "$MAP" || { echo "UNMAPPED: $f"; missing=1; }
done < <(ls "$IMG" | grep -P '[^\x00-\x7F]')
[ $missing -eq 0 ] || { echo "abort: unmapped files"; exit 1; }

# 2) 先全部改名
while IFS=$'\t' read -r old new; do
  [ -n "$old" ] || continue
  if [ -e "$IMG/$new" ]; then echo "COLLISION: $IMG/$new already exists"; exit 1; fi
  mv "$IMG/$old" "$IMG/$new" || exit 1
done < "$MAP"

# 3) 再统一替换引用
# 注意：必须按旧名长度降序替换，否则 下载.svg 会先命中 云端下载.svg 这类子串，
# 留下 云端download.svg 这样的半替换结果。
FILES=$(ls $PROJ/*.xaml $PROJ/*.cs)
sort -t"$(printf '\t')" -k1,1 -r "$MAP" | while IFS=$'\t' read -r old new; do
  [ -n "$old" ] || continue
  for x in $FILES; do
    grep -q "$old" "$x" && sed -i "s|$old|$new|g" "$x"
  done
done

# 4) 残留检查
echo "--- leftover non-ASCII image refs ---"
grep -hoE '[A-Za-z0-9_./-]*[^ -~][^"]*\.(svg|png|jpg|ico)' $PROJ/*.xaml $PROJ/*.cs | sort -u
echo "--- leftover CJK files in images ---"
ls "$IMG" | grep -P '[^\x00-\x7F]'
echo DONE
