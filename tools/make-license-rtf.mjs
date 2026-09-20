import fs from 'node:fs';

// 用法: node tools/make-license-rtf.mjs [LICENSE 路径] [输出 rtf 路径]
// 为什么不用 PowerShell：本机 PowerShell 5.1 跑这个脚本会在 AMSI 扫描里稳定段错误（rc=139），
// 而 Node 这边只需要把非 ASCII 转成 \u 转义，纯 ASCII 落盘，RTF 编码就不会错乱。
// 版本号不再手写：上一次就是改了脚本没重跑，安装包许可页上还挂着 1.2.0。这里直接从 setup 脚本读。
const src = process.argv[2] ?? 'LICENSE';
const dst = process.argv[3] ?? 'setup/license.rtf';

const iss = fs.readFileSync('setup/JiaHaoToolBox.iss', 'utf8');
const version = (iss.match(/#define MyAppVersion "([^"]+)"/) || [, '未知版本'])[1];
const appVerName = (iss.match(/^AppVerName=(.+)$/m) || [, ''])[1];
const badge = appVerName.replace(/^\{#MyAppName\}\s*/, '').replace(/^["']|["']$/g, '');

const esc = (s) => {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === '\\') out += '\\\\';
    else if (ch === '{') out += '\\{';
    else if (ch === '}') out += '\\}';
    else {
      const code = s.charCodeAt(i);
      out += code < 128 ? ch : '\\u' + (code > 32767 ? code - 65536 : code) + '?';
    }
  }
  return out;
};

const lines = fs.readFileSync(src, 'utf8').replace(/\r\n/g, '\n').split('\n');
const attribution =
  '本安装包为嘉豪工具箱（JiaHaoToolBox）安装程序。嘉豪工具箱是基于 GPL-3.0-or-later 许可证、' +
  '由紫罗兰工具箱（VioletToolBox）项目衍生修改而来的作品，上游版权归 Smart-Paocai 及其贡献者所有。' +
  '安装并使用本程序即表示你接受下列 GNU GPLv3 条款。';

const parts = [
  '{\\rtf1\\ansi\\ansicpg1252\\deff0\\deflang1033{\\fonttbl{\\f0\\fnil\\fcharset134 Consolas;}}\\viewkind4\\uc1',
  '\\pard\\qc\\b\\f0\\fs28 ' + esc('嘉豪工具箱 JiaHaoToolBox 安装程序') + '\\b0\\fs20\\par',
  '\\qc ' + esc(`版本 ${version}（${badge}）`) + '\\par\\par',
  '\\ql\\fs18 ' + esc(attribution) + '\\par\\par',
  '\\pard\\qc\\b\\fs24 ' + esc('GNU GENERAL PUBLIC LICENSE') + '\\b0\\fs20\\par\\par',
  ...lines.map((line) => '\\fs18 ' + esc(line) + '\\par'),
  '}',
];
fs.writeFileSync(dst, parts.join('\r\n'), 'ascii');
console.log(`${dst} <- ${src} + setup/JiaHaoToolBox.iss：${lines.length} 行, 版本 ${version}（${badge}）, ${fs.statSync(dst).size} 字节`);
