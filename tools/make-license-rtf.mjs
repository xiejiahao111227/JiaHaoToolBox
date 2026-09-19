import fs from 'node:fs';

const src = process.argv[2] ?? 'LICENSE';
const dst = process.argv[3] ?? 'setup/license.rtf';
const title = process.argv[4] ?? 'GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007';

const text = fs.readFileSync(src, 'utf8').replace(/\r\n/g, '\n');
// RTF: only ASCII is escaped by hand; codepage 65001 makes non-ASCII bytes valid UTF-8.
const esc = (s) => s.replace(/[\{}]/g, (c) => '\' + c)
  .replace(/[\u0080-\uFFFF]/g, (c) => '\u' + c.charCodeAt(c.toString() ? 0 : 0).toString() + '?'); // placeholder, replaced below
const body = text.split('\n').map((line) => {
  const safe = line.replace(/[\{}]/g, (c) => '\' + c);
  const uni = [...safe].map((ch) =>
    ch.codePointAt(0) < 128 ? ch : `\u${ch.codePointAt(0) & 0xffff}?`
  ).join('');
  return uni + '\par\n';
}).join('');

const rtf = `{\rtf1\ansi\ansicpg65001\deff0\deflang2052{\fonttbl{\f0\fnil\fcharset134 Consolas;}{\f1\fswiss\fcharset134 Microsoft YaHei;}}
\uc1
\pard\qc\b\f1\fs24 ${title.replace(/[\{}]/g, (c) => '\' + c)}\b0\par\par
\pard\qj\f0\fs16 ${body}\par}
`;
fs.writeFileSync(dst, rtf, 'latin1');
console.log(`${dst} <- ${src} (${text.length} chars -> ${rtf.length} bytes)`);
