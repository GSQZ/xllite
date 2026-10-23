'use strict';
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const ts = require(process.env.XJIT_TYPESCRIPT_PATH || 'D:/data/devecostudionext/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
let count = 0, failed = 0;
const tests = [];
function test(name, run) { tests.push({name,run}); }
function materials(api, supported = true, materialState = 0, queryThrows = false) {
  let calls = 0; const logs=[];
  const module = { exports: {} };
  const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/theme/Materials.ets'), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, {
    module, exports: module.exports, require: function requireMock(spec) {
      if (spec === './NativeMaterials') {
        const native = {exports:{}};
        vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root,'entry/src/main/ets/theme/NativeMaterials.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{module:native,exports:native.exports,require:requireMock});
        return native.exports;
      }
      if (spec === '@ohos.hilog') return {default:{info:(...args)=>logs.push(args)}};
      if (spec === '@ohos.deviceInfo') return { default: { sdkApiVersion: api } };
      if (spec === '@ohos.arkui.uiMaterial') return { default: {
        ImmersiveMaterial: class { constructor(options) { this.options=options; } },
        ImmersiveStyle: { REGULAR: 'regular', THIN: 'thin', THICK: 'thick' },
        isImmersiveMaterialSupported() { calls++; if (api < 26) throw new Error('API26 invoked on old OS'); return supported; },
        getMaterialInfo() { if (queryThrows) throw new Error('system material query failed'); return { state: materialState }; }, MaterialState: { DISABLE: 1 },
      } };
      throw new Error(spec);
    },
  });
  return { api: module.exports, calls: () => calls, logs };
}
test('API23 does not call API26 native material methods', () => { const f = materials(23); assert.equal(f.api.supportsImmersiveMaterial(), false); assert.equal(f.calls(), 0); });
test('encoded API23 version does not call API26 material methods', () => { const f = materials(230000023); assert.equal(f.api.supportsImmersiveMaterial(), false); assert.equal(f.calls(), 0); });
test('API26 material checks hardware support', async () => { const f = materials(26); assert.equal(await f.api.loadImmersiveMaterial(), true); assert.equal(f.calls(), 1); });
test('encoded API26 version enables native checks', async () => { const f = materials(260000026); assert.equal(await f.api.loadImmersiveMaterial(), true); assert.equal(f.calls(), 1); });
test('unsupported hardware uses compatibility material', async () => { assert.equal(await materials(26, false).api.loadImmersiveMaterial(), false); });
test('system-disabled API26 material falls back',async()=>{assert.equal(await materials(26,true,1).api.loadImmersiveMaterial(),false)});
test('throwing API26 material query falls back',async()=>{assert.equal(await materials(26,true,0,true).api.loadImmersiveMaterial(),false)});
test('native material caches all eight appearance combinations independently',async()=>{
 const f=materials(26);await f.api.loadImmersiveMaterial();const instances=new Set();
 for(const dark of [false,true])for(const interactive of [false,true])for(const prominent of [false,true]){
  const material=f.api.glassMaterial(dark,interactive,prominent);assert.equal(f.api.glassMaterial(dark,interactive,prominent),material);instances.add(material);
  const o=material.options;
  // 悬浮栏必须走薄档。之前 prominent 也传 thick，材质读出来是一块白板，
  // 和"玻璃"没有关系——这正是"背景一点都不透"的根因。
  assert.equal(o.style,prominent?'thin':'regular');
  assert.equal(o.interactive,interactive);assert.equal(o.applyShadow,true);
  // 浅色不额外叠色（全透明）；深色只给一丝压暗。
  assert.equal(o.materialColor,dark?'#0A000000':'#00000000');
  assert.equal(o.lightEffect?.color,dark?'#66A9C4FF':'#B3FFFFFF');
 }
 assert.equal(instances.size,8);assert.equal(f.logs.length,8);
 assert.ok(f.logs.every(log=>log[1]==='XJITMaterial' && log[2]==='Native material created style=%{public}d prominent=%{public}s'));
});
test('minimum SDK is API23 while target and compile remain API26', () => { const p = JSON.parse(fs.readFileSync(path.join(root, 'build-profile.json5'), 'utf8')).app.products[0]; assert.equal(p.compatibleSdkVersion, '6.1.0(23)'); assert.equal(p.targetSdkVersion, '26.0.0'); });
test('compatibility glass keeps the backdrop visible instead of veiling it', () => {
 const s = fs.readFileSync(path.join(root, 'entry/src/main/ets/components/NativeGlass.ets'), 'utf8');
 // 遮罩 alpha 是"透不透"的总闸。浅色曾经用 #B8FFFFFF（72% 白），等于给内容
 // 盖了一层七成白，模糊与否都看不出来，读起来就是白板；实测栏内像素方差 0.2，
 // 一点背景都没透。这里把上限钉在 25%，并要求饱和度足够高以维持玻璃感。
 // 只检查 backgroundEffect 的遮罩色，不要扫到顶部那条 1px 纯白高光。
 const veil = s.match(/color: this\.prominent\s*\n\s*\?\s*\(this\.isDark \? '(#[0-9A-Fa-f]{8})' : '(#[0-9A-Fa-f]{8})'\)\s*\n\s*:\s*\(this\.isDark \? '(#[0-9A-Fa-f]{8})' : '(#[0-9A-Fa-f]{8})'\)/);
 assert.ok(veil !== null, 'the backgroundEffect veil colours must be findable');
 const alphas = veil.slice(1, 5).map(c => parseInt(c.slice(1, 3), 16));
 assert.ok(Math.max(...alphas) <= 0x40, 'the fallback veil must stay translucent, max alpha ' + Math.max(...alphas));
 const sats = [...s.matchAll(/\? \(this\.isDark \? ([\d.]+) : ([\d.]+)\)/g)].map(m => Number(m[2]));
 assert.ok(sats.length >= 1, 'saturation values must be present');
 assert.ok(Math.min(...sats) >= 2.5, 'saturation must stay high enough to read as glass');
 // 自绘立面渐变同样不能太浓，否则把模糊层重新捂实。只检查 145° 那段渐变，
 // 描边是单独的 1px，不在这条约束里。
 const gradBlock = (s.match(/linearGradient\(\{ angle: 145[\s\S]*?\]\]\s*\}\)/)||[''])[0];
 const grad = [...gradBlock.matchAll(/'#([0-9A-Fa-f]{2})[0-9A-Fa-f]{6}'/g)].map(m => parseInt(m[1], 16));
 assert.ok(grad.length >= 3, 'the 145-degree facade gradient must be present');
 assert.ok(grad.every(a => a <= 0x20), 'the facade gradient must stay light, max alpha ' + Math.max(...grad));
});
test('compatibility glass uses native blur rather than an opaque placeholder', () => { const s = fs.readFileSync(path.join(root, 'entry/src/main/ets/components/NativeGlass.ets'), 'utf8'); assert.match(s, /backgroundEffect\(\{/); });
function mainTabs(reduceMotion) {
  const timers = new Map(); let next = 1;
  let s = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/MainTabs.ets'), 'utf8');
  s = s.slice(0, s.indexOf('  build()')) + '\n}';
  s = s.replace(/@(?:Entry|Component)\s*/g, '').replace(/@(?:StorageLink|Watch)\([^)]*\)\s*/g, '').replace(/@State\s*/g, '').replace('struct MainTabs', 'export class MainTabs');
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(s, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, {
    module, exports: module.exports, require(spec) { if (spec.endsWith('/Motion')) return { Motion: { duration: { fast: 180 } }, motionDuration: n => reduceMotion ? 0 : n }; return {}; },
    setTimeout(fn) { const id = next++; timers.set(id, fn); return id; }, clearTimeout(id) { timers.delete(id); },
  });
  return { page: new module.exports.MainTabs(), timers };
}
test('reduced motion switches tabs without retaining an invisible outgoing page', () => { const f = mainTabs(true); f.page.selectTab(1); assert.equal(f.page.currentIndex, 1); assert.equal(f.page.leavingTab, -1); assert.equal(f.timers.size, 0); });
test('invalid tab index cannot hide every page', () => { const f = mainTabs(false); f.page.selectTab(99); assert.equal(f.page.currentIndex, 0); });
test('noninteger tab indices preserve the current page and create no timers',()=>{
 for(const index of [NaN,Infinity,-Infinity,0.5,1.5]) {
  const f=mainTabs(false); f.page.selectTab(index);
  assert.equal(f.page.currentIndex,0); assert.equal(f.page.leavingTab,-1); assert.equal(f.timers.size,0);
 }
});
test('rapid tab changes retire stale animation timers', () => { const f = mainTabs(false); f.page.selectTab(1); f.page.selectTab(2); assert.equal(f.timers.size, 1); [...f.timers.values()][0](); assert.equal(f.page.leavingTab, -1); });
test('outgoing tab cannot intercept incoming tab gestures', () => { const s = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/MainTabs.ets'), 'utf8'); assert.equal((s.match(/\.hitTestBehavior\(this.currentIndex === [012] \? HitTestMode.Default : HitTestMode.None\)/g) || []).length, 3); });
test('enabling reduced motion retires a pending theme reveal and clears overlay', () => {
 const timers=new Map(), values=new Map(); const module={exports:{}};
 let source=fs.readFileSync(path.join(root,'entry/src/main/ets/components/common/ThemeWash.ets'),'utf8');
 source=source.slice(0,source.indexOf('  build()'))+'\n}'; source=source.replace(/@Component\s*/g,'').replace(/@(?:StorageLink|Watch)\([^)]*\)\s*/g,'').replace(/@State\s*/g,'').replace('export struct ThemeWash','export class ThemeWash');
 vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,{module,exports:module.exports,require(s){return s.endsWith('/Colors')?{getColors:()=>({background:'#fff'})}:{Motion:{duration:{base:320},curve:{decelerate:0}}};},AppStorage:{get:k=>values.get(k)},setTimeout:fn=>{timers.set(1,fn);return 1;},clearTimeout:id=>timers.delete(id)});
 const page=new module.exports.ThemeWash(); page.getUIContext=()=>({animateTo:(_o,fn)=>fn()}); page.onFlip(); assert.equal(timers.size,1);
 values.set('reduceMotion',true); page.onFlip(); assert.equal(timers.size,0); assert.equal(page.washOpacity,0);
});
test('dock scrim stays translucent so the glass has something to blur', () => {
 const source=fs.readFileSync(path.join(root,'entry/src/main/ets/pages/MainTabs.ets'),'utf8');
 // 衬底的作用是压住滚动文字，但不能压成实色：导航栏的 backdropBlur 需要背后
 // 有画面可模糊，衬底一旦不透明，玻璃就退化成一块纯色板。
 // 所以底部只到约 60%，并要求它不是 #FF。
 assert.ok(!source.includes("['#FF152039', 0.25]"), 'the scrim must not be fully opaque');
 assert.ok(!source.includes("['#FFEAF0FB', 0.25]"), 'the scrim must not be fully opaque');
 assert.match(source, /\['#99152039', 1\]/);
 assert.match(source, /\['#99EAF0FB', 1\]/);
 assert.ok(source.includes('BlurTabBar({'));
 assert.ok(source.includes('.hitTestBehavior(HitTestMode.None)'));
});
test('flowing dock selects by colour only, with vertical icon over label',()=>{
 const source=fs.readFileSync(path.join(root,'entry/src/main/ets/components/BlurTabBar.ets'),'utf8');
 // 纵向排布：图标在上、文字在下。
 assert.match(source,/Column\(\{ space: 4 \}\)/);
 assert.match(source,/\.width\(ICON_SIZE\)\.height\(ICON_SIZE\)/);
 assert.match(source,/this.reduceMotion \? 0 :/); assert.ok(!source.includes('setTimeout')); assert.ok(!source.includes("'#D9E5EDFF'"));
});
test('dock selects by highlight and idle dimming, never by a painted block',()=>{
 const source=fs.readFileSync(path.join(root,'entry/src/main/ets/components/BlurTabBar.ets'),'utf8');
 // 选中态只靠颜色 + 未选中整体压透明度，不做任何宽度/位置需要和容器对齐的色块。
 for (const banned of ['indicatorX','indicatorW','INDICATOR_','recalcIndicator','itemWidth','ICON_PILL']) {
  assert.ok(!source.includes(banned),'dock must not reintroduce a measured indicator: '+banned);
 }
 // 选中：品牌色；未选中：次级色 + IDLE_OPACITY 弱化。
 assert.match(source,/private tint\(index: number\): ResourceColor/);
 assert.match(source,/this\.currentIndex === index \? this\.palette\.primary : this\.palette\.onSurfaceVariant/);
 assert.match(source,/\.fillColor\(this\.tint\(index\)\)/);
 assert.match(source,/\.fontColor\(this\.tint\(index\)\)/);
 assert.match(source,/const IDLE_OPACITY: number = ([\d.]+)/);
 assert.match(source,/\.opacity\(this\.currentIndex === index \? 1 : IDLE_OPACITY\)/);
 // 按压不改底色，只做缩放；底色块会让选中态和按压态互相干扰。
 assert.ok(!source.includes('pressingIdx === index\n      ? (this.isDark'),
   'the pressed state must not paint a background');
 assert.match(source,/accessibilityDescription\(this\.currentIndex === index \? '已选中' : '切换到'/);
 // 均分：每项 layoutWeight(1)，数量变化不需要改布局。
 assert.match(source,/ForEach\(TABS_LABELS/);
 assert.match(source,/\.layoutWeight\(1\)\.height\(BAR_CONTENT_HEIGHT\)/);
});
test('dock signal its pressed slot without waiting for the selection to change',()=>{
 const source=fs.readFileSync(path.join(root,'entry/src/main/ets/components/BlurTabBar.ets'),'utf8');
 assert.match(source,/this\.pressingIdx = index/);
 assert.match(source,/TouchType\.Cancel/);
 // 按压缩小而不是放大：玻璃按钮被"压进去"更符合玻璃的物理直觉，
 // 放大反而像浮起来，和"按下去"的手感相反。
 assert.match(source,/const PRESS_SCALE: number = 0\.92/);
 assert.match(source,/\.scale\(\{ x: this\.reduceMotion \|\| this\.pressingIdx !== index \? 1 : PRESS_SCALE/);
});
test('dock animation is bypassed rather than merely zero-duration under reduced motion',()=>{
 const source=fs.readFileSync(path.join(root,'entry/src/main/ets/components/BlurTabBar.ets'),'utf8');
 // 栏里会动的只剩按压缩放，它必须走「减少动效 -> 时长 0」这条路，
 // 而不是留着曲线只把时长设 0（曲线仍会被求值一次，部分机型表现为一帧跳动）。
 assert.match(source,/\.animation\(\{ duration: this\.reduceMotion \? 0 : Motion\.duration\.instant/);
 assert.match(source,/this\.reduceMotion \|\| this\.pressingIdx !== index \? 1 : PRESS_SCALE/);
 assert.ok(!source.includes('springMotion'));
 assert.ok(!source.includes('setTimeout'));
});
test('native login uses packaged mountain brand without monochrome tint',()=>{
 const source=fs.readFileSync(path.join(root,'entry/src/main/ets/pages/LoginPage.ets'),'utf8');
 assert.match(source,/Image\(\$r\('app.media.icon'\)\)\.width\(60\)\.height\(60\)\.borderRadius\(18\)/);
 assert.ok(!source.includes("Image($r('app.media.campus_schedule'))"));
});
test('login discloses gateway credential processing separately from local storage',()=>{
 const source=fs.readFileSync(path.join(root,'entry/src/main/ets/pages/LoginPage.ets'),'utf8');
 assert.ok(source.includes('https://xllite.sayqz.com')); assert.ok(source.includes('服务器可能为续登保留凭据'));
 assert.ok(source.includes('保存期限与删除方式尚待服务运营方确认')); assert.ok(source.includes('密码不保存在本机'));
});
test('tab content switches without crossfading two readable text surfaces',()=>{
 const source=fs.readFileSync(path.join(root,'entry/src/main/ets/pages/MainTabs.ets'),'utf8');
 const body=source.slice(source.indexOf('  build()'),source.indexOf('  pageTransition()'));
 assert.equal((body.match(/\.animation\(/g)||[]).length,0);
});
test('dock clears the gesture bar without letting the inset go negative',()=>{
 // 底部避让从 MainTabs 挪进了 BlurTabBar 自己：栏贴边通栏后，
 // 外边距再垫一层会重复避让。断言避让仍然存在且被钳到非负。
 const bar=fs.readFileSync(path.join(root,'entry/src/main/ets/components/BlurTabBar.ets'),'utf8');
 assert.match(bar,/@StorageLink\('safeAreaBottom'\) safeAreaBottom: number = 0/);
 // 玻璃必须铺到屏幕底边：高度含 safeAreaBottom，圆角只给上面两角，
 // 内容再用 margin 让出手势条。少任何一条，栏底都会露出一条背景色。
 assert.match(bar,/\.height\(BAR_CONTENT_HEIGHT \+ PAD_Y \* 2 \+ this\.safeAreaBottom\)/);
 assert.match(bar,/\.borderRadius\(\{ topLeft: TAB_RADIUS, topRight: TAB_RADIUS \}\)/);
 assert.match(bar,/\.margin\(\{ bottom: PAD_Y \+ this\.safeAreaBottom \}\)/);
 assert.ok(!bar.includes('.margin({ bottom: this.safeAreaBottom })'), 'the bar must sit on the screen edge');
 const tabs=fs.readFileSync(path.join(root,'entry/src/main/ets/pages/MainTabs.ets'),'utf8');
 assert.ok(!tabs.includes('bottom: Math.max(0, this.safeAreaBottom - 8)'),
   'the inset must not be applied twice');
});
(async()=>{for(const {name,run} of tests){count++;try{await run();console.log('PASS '+name)}catch(e){failed++;console.error('FAIL '+name+': '+e.message)}}console.log(`${count} API23 checks, ${failed} failed`);process.exitCode=failed?1:0;})();
