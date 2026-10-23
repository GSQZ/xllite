// Reusable token audit. Checks opaque text/surface pairs, not rendered translucent pixels.
'use strict';
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const tsFile = process.env.XJIT_TYPESCRIPT_PATH || 'D:/data/devecostudionext/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js';
if (!fs.existsSync(tsFile)) throw new Error('Existing SDK TypeScript missing; no download attempted.');
const ts = require(tsFile), moduleObject = { exports: {} };
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/theme/Colors.ets'), 'utf8');
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText,
  { exports: moduleObject.exports, module: moduleObject });
function luminance(hex) {
  const channels = hex.replace('#', '').match(/.{2}/g).map(s => parseInt(s, 16) / 255);
  const linear = channels.map(c => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722;
}
function contrast(text, surface) { const a = luminance(text), b = luminance(surface); return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05); }
const pairs = [];
function check(theme, role, text, surface) {
  const ratio = contrast(text, surface); pairs.push({ theme, role, text, surface, ratio: +ratio.toFixed(3), pass: ratio >= 4.5 });
}
for (const [name, p] of [['light', moduleObject.exports.LightColors], ['dark', moduleObject.exports.DarkColors]]) {
  for (const surface of ['background', 'surface', 'surfaceVariant']) {
    check(name, 'body / ' + surface, p.onSurface, p[surface]);
    check(name, 'secondary / ' + surface, p.onSurfaceVariant, p[surface]);
  }
  check(name, 'primary button', p.onPrimary, p.primary);
  check(name, 'primary container', p.onPrimaryContainer, p.primaryContainer);
  check(name, 'accent button', p.onAccent, p.accent);
  check(name, 'accent container', p.onAccentContainer, p.accentContainer);
  p.courseColors.forEach((color, i) => check(name, 'course ' + (i + 1), name === 'light' ? '#FFFFFF' : '#0B0E14', color));
}
// WeekOverview 现在由 courseColors + withAlpha 派生配色：背景是同色降透明度。
// 半透明背景必须先合成到页面底色上才谈得上对比度，所以这里按同一公式复算。
function blend(hex, alpha, base) {
  const fg = hex.replace('#', '').match(/.{2}/g).map(s => parseInt(s, 16) / 255);
  const bg = base.replace('#', '').match(/.{2}/g).map(s => parseInt(s, 16) / 255);
  return '#' + fg.map((c, i) => Math.round((c * alpha + bg[i] * (1 - alpha)) * 255))
    .map(c => c.toString(16).padStart(2, '0')).join('');
}
for (const [name, p, base, alpha] of [['light', moduleObject.exports.LightColors, '#FFFFFF', 0.10],
  ['dark', moduleObject.exports.DarkColors, '#0B0E14', 0.20]]) {
  p.courseColors.forEach((color, i) =>
    check(name, 'week overview course ' + (i + 1), color, blend(color, alpha, base)));
}
const report = { checkedAt: new Date().toISOString(), scope: 'Opaque text tokens; translucent/native materials require screenshot review.', threshold: 4.5,
  minimum: Math.min(...pairs.map(p => p.ratio)), checks: pairs.length, failed: pairs.filter(p => !p.pass), pairs };
// 只在结论变化时落盘。快照文件被跟踪，每次跑测试都换时间戳会把工作区弄脏，
// 提交里就会混进一条与对比度无关的改动。
const snapshotPath = path.join(root, '.wolf/quality-contrast.json');
const previous = (() => {
  try { return JSON.parse(fs.readFileSync(snapshotPath, 'utf8')); } catch (_error) { return null; }
})();
const sameResult = previous !== null && previous.minimum === report.minimum
  && previous.checks === report.checks && JSON.stringify(previous.pairs) === JSON.stringify(report.pairs)
  && (previous.failed || []).length === report.failed.length;
if (sameResult) report.checkedAt = previous.checkedAt;
fs.mkdirSync(path.join(root, '.wolf'), { recursive: true });
fs.writeFileSync(snapshotPath, JSON.stringify(report, null, 2));
console.log(report.checks + ' token contrast checks; minimum ' + report.minimum + ':1; ' + report.failed.length + ' failed.');
for (const pair of report.failed) console.error(pair);
process.exitCode = report.failed.length ? 1 : 0;
