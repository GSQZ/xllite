// 远程提交前的范围审核。默认审 index（即将提交的内容），可用 --range <rev> 审已提交范围。
// 只用于拦截，不修改任何文件。命中禁项以退出码 1 结束，让推送前的链条停住。
'use strict';
const { execFileSync } = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const rangeIdx = args.indexOf('--range');
const range = rangeIdx >= 0 ? args[rangeIdx + 1] : null;

function git(argv, opts = {}) {
  // -z：路径按 NUL 分隔原样返回。Git 默认把非 ASCII 文件名转义成八进制，
  // 用普通 ls-files 加正则会漏掉所有中文名文件，这里必须走 -z。
  return execFileSync('git', argv, { cwd: root, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, ...opts });
}
function nulSplit(text) { return text.split('\0').filter(Boolean); }

// 待审文件清单：默认 index，指定 --range 时审该范围内改动过的路径。
let files;
if (range) {
  files = nulSplit(git(['diff', '--name-only', '-z', '--diff-filter=ACMR', range]));
} else {
  files = nulSplit(git(['diff', '--cached', '--name-only', '-z', '--diff-filter=ACMR']));
}
if (files.length === 0) {
  // 无待提交内容时退化为审 HEAD 树的整体范围，避免空跑等于放行。
  files = nulSplit(git(['ls-tree', '-r', '--name-only', '-z', 'HEAD']));
}

// 路径规则：与项目安装、构建、部署无关的内容不应进远程仓库。
const pathRules = [
  ['附属项目', /^(quiz-network|volc-ai-proxy)\//],
  ['编辑器/AI 工具配置', /(^|\/)\.(claude|codex|cursor)\//],
  ['开发过程日志与记忆', /(^|\/)\.wolf\/(?!(?:[^/]*\.json)$)/],
  ['构建解包产物', /(^|\/)docs\/simulator-verify-[^/]*\//],
  ['SDK 本地文档', /(^|\/)docs\/html\//],
  ['计划稿与交接记录', /docs\/(?:\d{4}-\d{2}-\d{2}-(?:NEXT-SESSION-HANDOFF|TODO-BATCH|REVISION-BATCH|ACCEPTANCE-REFRESH|REMAINING-ACCEPTANCE|CONTRACT-RECHECK)|STORE-READINESS|PROJECT-STATUS)\.md$/],
  ['逆向与反编译记录', /(逆向|反编译|反汇编|脱壳|jadx|apktool|smali|dex2jar)/i],
  ['一次性探测脚本', /tools\/(?:probe|scratch|tmp|adhoc)[-_]/i],
  ['本机验证临时目录', /(^|\/)_?(?:verify|scratch|tmp|temp)[-_]?(?:tmp|dir|out)?\//i],
  ['源码备份与临时副本', /\.(?:bak|orig|rej)(?:-|$)|(^|\/)[^/]*\.bak-$/],
  ['签名与密钥材料', /\.(?:jks|p12|pem|key|cer|csr|p7b)$|xjit-debug-profile\.json$/i],
  ['环境变量文件', /(^|\/)\.env$|(^|\/)\.env\.(?!example$)/],
];
// 根目录散落的历史报告也不属于交付物。
const rootReport = /^[^/]*(?:实施报告|分析报告|逆向|刷题)[^/]*\.(?:md|html)$/;

// 内容规则：只对可读文本生效，二进制跳过。
// 刻意收窄：逆向类词只在指向他人产物时算命中，本工程对自身构建产物的依赖核查（ark_disasm 看 modules.abc）
// 属于构建验证，是交付证据；cursor 作为编辑器的语境词另行处理，避免与 CSS 的 cursor 属性撞车。
const contentRules = [
  ['AI 痕迹', new RegExp([
    '\\b(?:Claude|ChatGPT|Copilot|Cursor\\s*(?:IDE|Editor|AI)|GPT-[45]|DeepSeek|通义千问|文心一言)\\b',
    '(?:由\\s*AI|AI\\s*生成|AI\\s*辅助|大模型生成|提示词注入)',
  ].join('|'), 'i')],
  ['项目计划书语气', /(?:下一轮改造需求|本轮计划|排期|工期|阶段计划|里程碑|交付计划|待办批次|交接记录)/],
  ['逆向记录', new RegExp([
    '(?:apk|ipa|har|apks)\\s*逆向', '逆向分析', '反编译\\s*(?:他人|官方|第三方)',
    '(?:jadx|apktool|dex2jar)', '脱壳', 'smali\\s*代码', '破解\\s*(?:签名|校验)',
  ].join('|'), 'i')],
];
const textExt = new Set(['.ets', '.ts', '.js', '.cjs', '.mjs', '.json', '.json5', '.md', '.html',
  '.css', '.ps1', '.sh', '.py', '.yaml', '.yml', '.txt', '.gradle', '.properties', '.svg']);
// 样式文件里 cursor 是合法 CSS 属性，不做 AI 工具词判定。
const styleExt = new Set(['.css', '.html', '.svg']);

const findings = [];
for (const file of files) {
  for (const [label, re] of pathRules) {
    if (re.test(file)) findings.push({ kind: 'path', label, file });
  }
  if (rootReport.test(file)) findings.push({ kind: 'path', label: '根目录历史报告', file });

  const ext = path.extname(file).toLowerCase();
  if (!textExt.has(ext)) continue;
  // 审核器自身必须写出这些关键词才能构成规则，不对它做内容判定。
  if (file === 'tools/scope-audit.cjs') continue;
  let text;
  try { text = git(['show', `:${file}`], { stdio: ['ignore', 'pipe', 'ignore'] }); }
  catch { continue; }
  if (text.length > 2 * 1024 * 1024) continue;
  for (const [label, re] of contentRules) {
    if (label === 'AI 痕迹' && styleExt.has(ext)) continue;
    const hit = re.exec(text);
    if (hit) {
      const line = text.slice(0, hit.index).split('\n').length;
      findings.push({ kind: 'content', label, file, line, excerpt: hit[0].slice(0, 60) });
    }
  }
}

const scope = range ? `范围 ${range}` : '待提交内容';
if (findings.length === 0) {
  console.log(`范围审核通过：${scope}，检查 ${files.length} 个文件，未命中禁项。`);
  process.exit(0);
}
console.error(`范围审核未通过：${scope}，命中 ${findings.length} 项`);
for (const f of findings) {
  if (f.kind === 'path') console.error(`  [路径] ${f.label}: ${f.file}`);
  else console.error(`  [内容] ${f.label}: ${f.file}:${f.line}  「${f.excerpt}」`);
}
console.error('\n这些内容不随远程仓库分发。确认无用后从索引移除（git rm --cached 保留本机文件），');
console.error('确属交付物则调整 .gitignore 与审核规则。');
process.exit(1);
