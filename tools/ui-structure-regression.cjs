'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const pages = path.join(root, 'entry/src/main/ets/pages');
let checks = 0;
let failed = 0;
function check(name, run) {
  checks++;
  try { run(); console.log('PASS ' + name); }
  catch (error) { failed++; console.error('FAIL ' + name + ': ' + error.message); }
}
for (const file of fs.readdirSync(pages).filter(name => name.endsWith('.ets'))) {
  const source = fs.readFileSync(path.join(pages, file), 'utf8');
  const transition = source.match(/pageTransition\(\):\s*void\s*\{([\s\S]*?)\n  \}/);
  if (!transition) continue;
  check(file + ' transition contains no local declarations', () => {
    assert.doesNotMatch(transition[1], /\b(?:const|let|var)\s/,
      'ArkUI transition builders require component syntax; inline the duration expression');
    assert.match(transition[1], /duration:\s*motionDuration\(Motion\.duration\.base\)/);
  });
}
check('LoginPage theme overlay remains inside the root Stack', () => {
  const source = fs.readFileSync(path.join(pages, 'LoginPage.ets'), 'utf8');
  assert.match(source, /\n      ThemeWash\(\)\n    \}\.width\('100%'\)\.height\('100%'\)\.backgroundColor\(this\.palette\.background\)\n  \}/);
});
check('training plan entry is gone and nothing links to a removed page', () => {
  const profile = fs.readFileSync(path.join(pages, 'ProfileTab.ets'), 'utf8');
  const constants = fs.readFileSync(path.join(root, 'entry/src/main/ets/utils/Constants.ets'), 'utf8');
  // 培养方案没有真实数据来源（网关返回空的 training 集合），入口与页面一并移除。
  // 这里钉住三件事：没人再链到那个页面、服务表里没有它、页面文件确实不在。
  assert.doesNotMatch(profile, /'TrainingPage'/);
  assert.doesNotMatch(constants, /jw\.training/);
  assert.doesNotMatch(constants, /培养方案/);
  assert.equal(fs.existsSync(path.join(pages, 'TrainingPage.ets')), false);
});
check('unresolved course sections are labelled instead of rendered as 00:00', () => {
  const schedule = fs.readFileSync(path.join(pages, 'ScheduleTab.ets'), 'utf8');
  assert.match(schedule, /resolved: sectionsResolved\(/, 'ScheduleTab must carry a resolved flag per course');
  assert.match(schedule, /courseTimeText\(/, 'ScheduleTab must label courses whose section time cannot be resolved');
  assert.match(schedule, /item\.resolved/, 'ScheduleTab must branch on the resolved flag when rendering times');
  assert.match(schedule, /if \(item\.resolved[^\n]*this\.liveEnabled/, 'live view must not be offered for unresolvable sections');
  const home = fs.readFileSync(path.join(pages, 'HomeTab.ets'), 'utf8');
  assert.match(home, /resolved: sectionsResolved\(/, 'HomeTab must carry a resolved flag per course');
  assert.match(home, /courseTimeText\(/, 'HomeTab must label unresolved courses instead of a midnight time');
});
console.log(`${checks} UI structure checks, ${failed} failed`);
process.exitCode = failed ? 1 : 0;
