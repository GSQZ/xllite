'use strict';
// Runs the actual non-rendering page methods with mocked API, clock and timers.
// ArkUI build/builder bodies are deliberately excluded; device UI is checked separately.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const tsPath = process.env.XJIT_TYPESCRIPT_PATH || 'D:/data/devecostudionext/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js';
if (!fs.existsSync(tsPath)) throw new Error('Existing TypeScript SDK missing; no download attempted.');
const ts = require(tsPath), tests = [];
function test(name, run) { tests.push({ name, run }); }
function gate() { let resolve, reject; const promise = new Promise((r, j) => { resolve = r; reject = j; }); return { promise, resolve, reject }; }
async function until(predicate) { for (let i = 0; i < 300; i++) { if (predicate()) return; await Promise.resolve(); } throw new Error('Asynchronous checkpoint missing'); }
function fixture(name) {
  const state = { epoch: 1, cardEpoch: 1, username: 'sample-student', now: 100000, requests: [], timers: new Map(), nextTimer: 1, toasts: [] };
  let rowsModule = { exports: {} };
  const rows = fs.readFileSync(path.join(root, 'entry/src/main/ets/utils/ListDataSource.ets'), 'utf8');
  vm.runInNewContext(ts.transpileModule(rows, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, { exports: rowsModule.exports, module: rowsModule });
  let source = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/' + name + '.ets'), 'utf8').replace(/\r\n/g, '\n');
  const bodyEnd = source.search(/  (?:@Builder|build\(\))/);
  if (bodyEnd < 0) throw new Error('Page logic boundary missing: ' + name);
  source = source.slice(0, bodyEnd) + '\n}\n';
  source = source.replace(/@(?:Entry|Component)\s*/g, '').replace(/@(?:StorageLink|Watch)\([^)]*\)\s*/g, '').replace(/@State\s*/g, '').replace(/@Prop\s*/g, '')
    .replace('export struct ' + name, 'struct ' + name).replace('struct ' + name, 'export class ' + name);
  const module = { exports: {} };
  const context = {
    AppStorage: { get:()=>7, setOrCreate(){} },
    exports: module.exports, module, console, Date: class extends Date { static now() { return state.now; } },
    setTimeout(fn, delay) { const id = state.nextTimer++; state.timers.set(id, { fn, delay, interval: false }); return id; },
    setInterval(fn, delay) { const id = state.nextTimer++; state.timers.set(id, { fn, delay, interval: true }); return id; },
    clearTimeout(id) { state.timers.delete(id); }, clearInterval(id) { state.timers.delete(id); },
    require(spec) {
      if (spec.endsWith('/ApiService')) return { callFeature(feature, username, params) { const deferred = gate(); state.requests.push({ feature, username, params, ...deferred }); return deferred.promise; } };
      if (spec.endsWith('/AuthManager')) return { getUsername: () => state.username, loadElectricityRoom: async () => state.roomLoad ? await state.roomLoad : state.room || '', saveElectricityRoom: async value => { if (state.roomSaveFails) return false; state.room = value; return true; }, getPassword: () => 'mock', getCardSessionEpoch: () => state.cardEpoch, getCardAccountLabel: () => '测试校园卡' };
      if (spec.endsWith('/TodoService')) return {async addTodo(draft){state.todoAdds=(state.todoAdds||0)+1;if(state.todoPending)await state.todoPending;return []},toggleTodo:async()=>{if(state.todoActionPending)return await state.todoActionPending;throw new Error('fixture disk failure')},deleteTodo:async()=>{if(state.todoActionPending)return await state.todoActionPending;throw new Error('fixture disk failure')},disableTodoReminders:async()=>{state.todoDisabled=true;if(state.reminderServicePending)await state.reminderServicePending},registerTodoReminders:async()=>{state.todoRegisters=(state.todoRegisters||0)+1;if(state.reminderServicePending)await state.reminderServicePending;return 2},getTodoLiveCleanupStatus:()=>state.liveCleanupStatus||'',retryTodoLiveCleanup:async()=>{state.liveCleanupStatus=''},getTodoReminderStatus:()=> 'fixture status',restoreTodoReminderStatus:async()=>{state.todoRestores=(state.todoRestores||0)+1},refreshTodoWidgets:async()=>{state.todoRefreshes=(state.todoRefreshes||0)+1;if(state.todoRefreshFailure)throw Error('fixture widget failure')},loadTodos:async()=>state.todoLoad?await state.todoLoad:[],countOpenTodos:()=>0};
      if (spec.endsWith('/LiveViewService')) return {startTodoLiveView:async()=>state.livePending?await state.livePending:{ok:true}};
      if (spec.endsWith('/Colors')) return {getColors:()=>({})};
      if (spec.endsWith('/MemoryCache')) return { getCacheEpoch: () => state.epoch };
      if (spec.endsWith('/SemesterService')) return {getTerm:()=> 'fixture-term'};
      if (spec.endsWith('/UiStateCache')) return { loadUiState() { return state.savedUi || null; }, saveUiState() {}, clearUiState() {} };
      if (spec.endsWith('/ListDataSource')) return rowsModule.exports;
      if (spec.endsWith('/XlliteGateway')) return {async logoutGatewayAccount(){state.logouts=(state.logouts||0)+1;if(state.logoutFailure)throw Error('fixture cleanup failed')}};
      if (spec.endsWith('/RouterHelper')) return { safeBack() {} };
      if (spec.endsWith('/ToastHelper')) return { safeToast(_ctx, text) { state.toasts.push(text); } };
      if (spec === '@ohos.notificationManager') return {default:{isNotificationEnabled:async()=>state.notificationPending?await state.notificationPending:true,requestEnableNotification:async()=>{}}};
      if (spec === '@ohos.web.webview') return { default: { WebviewController: class {} } };
      // Logger 封装会按级别分派，缺任一方法都会让服务层一打日志就抛 TypeError。
      if (spec === '@ohos.hilog') return { default: { debug() {}, info() {}, warn() {}, error() {} } };
      if (spec === '@ohos.util') return { default: {} };
      return {};
    },
  };
  vm.runInNewContext(ts.transpileModule(source, { fileName: name + '.ts', compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, context);
  const page = new module.exports[name](); page.getUIContext = () => ({}); if(name==='TodoTab')page.alive=true;
  return { page, state };
}
test('profile logout cleanup failure is visible and leaves retry enabled',async()=>{
 const {page,state}=fixture('ProfileTab');page.alive=true;state.logoutFailure=true;await page.handleLogout();assert.equal(page.loggingOut,false);assert.ok(state.toasts.at(-1).includes('清理未完成'));await page.handleLogout();assert.equal(state.logouts,2);
 page.alive=false;await page.handleLogout();assert.equal(state.toasts.length,2);
});
test('electricity restores saved room and queries without rebinding',async()=>{
 const {page,state}=fixture('ElectricityPage');state.room='9#312';
 const task=page.aboutToAppear();for(let i=0;i<20&&state.requests.length===0;i++)await Promise.resolve();
 assert.equal(state.requests.length,1);assert.equal(state.requests[0].params.roomQuery,'9#312');
 state.requests[0].resolve({ok:true,data:{}});await task;assert.equal(page.step,2);
});
test('electricity successful query remembers room while failed query preserves binding',async()=>{
 const {page,state}=fixture('ElectricityPage');page.alive=true;page.roomQuery=' 9#312 ';
 const task=page.queryElectricity();state.requests[0].resolve({ok:true,data:{}});await task;assert.equal(state.room,'9#312');
 page.roomQuery='3#312';const fail=page.queryElectricity();state.requests[1].resolve({ok:false,error:'fixture'});await fail;assert.equal(state.room,'9#312');
});
test('electricity change room retires requests and keeps stored binding until success',()=>{
 const {page,state}=fixture('ElectricityPage');page.alive=true;page.step=2;page.electricity={};state.room='9#312';
 const version=page.requestVersion;page.changeRoom();assert.equal(page.step,1);assert.equal(page.electricity,null);assert.ok(page.requestVersion>version);assert.equal(state.room,'9#312');
 page.paying=true;page.step=3;page.changeRoom();assert.equal(page.step,3);
});
test('electricity reports an unsaved room binding instead of staying silent',async()=>{
 // 宿舍绑定是「记住上次输入」的便利功能，失败不影响本次查询，但用户要知道
 // 下次还得重输。原先 saveElectricityRoom 静默 return，调用方的 catch 永不触发。
 const {page,state}=fixture('ElectricityPage');page.alive=true;page.roomQuery='9#312';state.roomSaveFails=true;
 const task=page.queryElectricity();state.requests[0].resolve({ok:true,data:{}});await task;
 assert.equal(page.step,2,'the query itself must still succeed');
 assert.match(page.errorMsg,/宿舍绑定未保存/);
});
test('electricity results offer refresh independently from change room',()=>{
 const source=fs.readFileSync(path.join(root,'entry/src/main/ets/pages/ElectricityPage.ets'),'utf8');
 assert.match(source,/Button\(this.loading \? '刷新中…' : '刷新电量'\)/);assert.match(source,/Button\('更换宿舍'\)/);
});
// 支付提交后的那一屏只是「请求已提交」，不是支付成功。用成功色或粗体渲染会让
// 用户把这一屏读成结果页，所以从源码层面禁止回退到 success 色。
test('electricity submission result never renders as success',()=>{
 const source=fs.readFileSync(path.join(root,'entry/src/main/ets/pages/ElectricityPage.ets'),'utf8');
 assert.match(source,/支付请求已提交/);
 assert.match(source,/请到一卡通账户核对到账结果/);
 assert.doesNotMatch(source,/fontColor\(getColors\(this\.isDark\)\.success\)/);
});
test('electricity restore errors from a retired account do not alter the page',async()=>{
 const {page,state}=fixture('ElectricityPage');let reject;
 state.roomLoad=new Promise((_resolve,r)=>{reject=r});const task=page.aboutToAppear();
 state.epoch++;state.username='other-account';reject(new Error('fixture read failure'));await task;
 assert.equal(page.errorMsg,'');assert.equal(state.requests.length,0);
});
test('todo explicit time accepts future only and can be cleared',()=>{
 const {page,state}=fixture('TodoTab');const date=new Date(2026,9,18);
 page.selectDueTime(date,20,0);assert.equal(page.dueAt,new Date(2026,9,18,20,0).getTime());assert.ok(page.dueInput.includes('20:00'));
 const prior=page.dueAt;page.selectDueTime(date,24,0);assert.equal(page.dueAt,prior);
 page.selectDueTime(new Date(1970,0,1),0,0);assert.equal(page.dueAt,prior);
 page.clearDueTime();assert.equal(page.dueAt,undefined);assert.equal(page.dueInput,'');
});
test('todo add revalidates time and deduplicates pending submission',async()=>{
 const {page,state}=fixture('TodoTab');page.titleInput='Study';page.dueAt=state.now;await page.handleAdd();assert.equal(state.todoAdds||0,0);
 page.dueAt=state.now+60000;let resolve;state.todoPending=new Promise(r=>resolve=r);const first=page.handleAdd();await page.handleAdd();assert.equal(state.todoAdds,1);resolve();await first;assert.equal(page.saving,false);
});
test('todo add failure preserves input and unlocks retry',async()=>{
 const {page,state}=fixture('TodoTab');page.titleInput='Study';state.todoPending=Promise.reject(new Error('fixture'));
 await page.handleAdd();assert.equal(page.titleInput,'Study');assert.equal(page.saving,false);assert.ok(state.toasts.length>0);
});
test('todo toggle and delete errors retain visible rows and report retry',async()=>{
 const {page,state}=fixture('TodoTab');const item={id:'fixture',title:'Study'};page.todos=[item];
 await page.handleToggle(item);assert.equal(page.todos[0],item);assert.equal(state.toasts.length,1);
 await page.handleDelete(item);assert.equal(page.todos[0],item);assert.equal(state.toasts.length,2);
});
test('todo explicit reminder action reports actual registration count',async()=>{
 const {page,state}=fixture('TodoTab');await page.handleReminders();assert.equal(state.todoRegisters,1);assert.ok(state.toasts.at(-1).includes('2'));assert.equal(page.reminderBusy,false);
});
test('todo reminder cancellation reports success and unlocks controls',async()=>{
 const {page,state}=fixture('TodoTab');await page.handleDisableReminders();assert.equal(state.todoDisabled,true);assert.equal(page.reminderBusy,false);assert.ok(state.toasts.at(-1).includes('已取消'));
});
test('todo initial load ignores results after disappearance or account change',async()=>{
 for(const mode of ['disappear','account']){
  const {page,state}=fixture('TodoTab');let resolve;state.todoLoad=new Promise(r=>resolve=r);const task=page.aboutToAppear();
  if(mode==='disappear')page.aboutToDisappear();else{state.epoch++;state.username='other'}
  resolve([{id:'old',title:'Private'}]);await task;assert.equal(page.todos.length,0);assert.equal(state.todoRestores||0,0);assert.equal(state.todoRefreshes||0,0);
 }
});
test('todo add completion does not clear form after page disappearance',async()=>{
 const {page,state}=fixture('TodoTab');page.alive=true;page.titleInput='Study';let resolve;state.todoPending=new Promise(r=>resolve=r);
 const task=page.handleAdd();page.aboutToDisappear();resolve();await task;assert.equal(page.titleInput,'Study');assert.equal(state.toasts.length,0);
});
test('todo toggle delete callbacks ignore retired pages and accounts',async()=>{
 for(const method of ['handleToggle','handleDelete'])for(const mode of ['disappear','account']){
  const {page,state}=fixture('TodoTab');const old={id:'old',title:'Study'};page.todos=[old];let resolve;
  state.todoActionPending=new Promise(r=>resolve=r);const task=page[method](old);
  if(mode==='disappear')page.aboutToDisappear();else{state.epoch++;state.username='other'}
  resolve([]);await task;assert.equal(page.todos[0],old);assert.equal(state.toasts.length,0);
 }
});
test('todo reminder permission wait cannot register after page or account retires',async()=>{
 for(const mode of ['disappear','account']){
  const {page,state}=fixture('TodoTab');let resolve;state.notificationPending=new Promise(r=>resolve=r);
  const task=page.handleReminders();if(mode==='disappear')page.aboutToDisappear();else{state.epoch++;state.username='other'}
  resolve(true);await task;assert.equal(state.todoRegisters||0,0);assert.equal(state.toasts.length,0);
 }
});
test('todo live view result only reports to the current page and account',async()=>{
 for(const mode of ['active','disappear','account']){
  const {page,state}=fixture('TodoTab');let resolve;state.livePending=new Promise(r=>resolve=r);const task=page.handleLiveView({id:'task',title:'Study'});
  if(mode==='disappear')page.aboutToDisappear();if(mode==='account'){state.epoch++;state.username='other'}
  resolve({ok:true});await task;assert.equal(state.toasts.length,mode==='active'?1:0);
 }
});
test('todo live view thrown errors are contained only for active page',async()=>{
 for(const mode of ['active','disappear']){
  const {page,state}=fixture('TodoTab');let reject;state.livePending=new Promise((_r,j)=>reject=j);const task=page.handleLiveView({id:'task',title:'Study'});
  if(mode==='disappear')page.aboutToDisappear();reject(Error('fixture native failure'));await task;
  assert.equal(state.toasts.length,mode==='active'?1:0);
 }
});
test('todo live cleanup retry refreshes visible failure status',async()=>{
 const {page,state}=fixture('TodoTab');state.liveCleanupStatus='未完成';page.liveCleanupStatus='未完成';await page.handleRetryLiveCleanup();assert.equal(page.liveCleanupStatus,'');assert.equal(page.liveCleanupBusy,false);
});
test('todo initial read failure is contained and does not refresh empty widget',async()=>{
 const {page,state}=fixture('TodoTab');let reject;state.todoLoad=new Promise((_r,j)=>reject=j);const task=page.aboutToAppear();reject(Error('fixture read failure'));await task;
 assert.ok(state.toasts.at(-1).includes('读取未完成'));assert.equal(state.todoRefreshes||0,0);assert.ok(page.loadError.includes('读取未完成'));
 state.todoLoad=null;page.titleInput='Keep draft';await page.handleReloadTodos();assert.equal(page.loadError,'');assert.equal(page.titleInput,'Keep draft');assert.equal(page.reloadBusy,false);assert.equal(state.todoRestores,1);assert.equal(state.todoRefreshes,1);
});
test('todo reload drops retired results without refreshing companion data',async()=>{
 for(const mode of ['disappear','account']){
  const {page,state}=fixture('TodoTab');let resolve;state.todoLoad=new Promise(r=>resolve=r);page.loadError='original error';const task=page.handleReloadTodos();
  if(mode==='disappear')page.aboutToDisappear();else{state.epoch++;state.username='other'}resolve([{id:'private'}]);await task;
  assert.equal(page.todos.length,0);assert.equal(page.loadError,'original error');assert.equal(state.todoRestores||0,0);assert.equal(state.todoRefreshes||0,0);assert.equal(state.toasts.length,0);
 }
});
test('todo reload widget failure never relabels successful task read as a failure',async()=>{
 const {page,state}=fixture('TodoTab');state.todoRefreshFailure=true;page.loadError='old failure';await page.handleReloadTodos();
 assert.equal(page.loadError,'');assert.equal(page.reloadBusy,false);assert.ok(state.toasts.at(-1).includes('卡片暂未刷新'));
});
test('todo direct entry without account never loads private tasks or companion state',async()=>{
 const {page,state}=fixture('TodoTab');state.username='';await page.aboutToAppear();assert.ok(page.loadError.includes('登录'));assert.equal(state.todoRestores||0,0);assert.equal(state.todoRefreshes||0,0);
 page.titleInput='Private';await page.handleAdd();assert.equal(state.todoAdds||0,0);
 await page.handleReloadTodos();assert.ok(page.loadError.includes('登录'));
});
test('todo draft survives same-account reentry but not another session',async()=>{
 const {page,state}=fixture('TodoTab');await page.aboutToAppear();page.titleInput='Private';page.noteInput='Secret';page.dueAt=200000;
 page.aboutToDisappear();await page.aboutToAppear();assert.equal(page.titleInput,'Private');
 page.aboutToDisappear();state.username='other';state.epoch++;await page.aboutToAppear();assert.equal(page.titleInput,'');assert.equal(page.noteInput,'');assert.equal(page.dueAt,undefined);
});
test('todo stale controls stop after account switch without page reentry',async()=>{
 const {page,state}=fixture('TodoTab');await page.aboutToAppear();page.titleInput='Old private';page.todos=[{id:'old'}];state.username='other';state.epoch++;
 await page.handleReminders();assert.equal(state.todoRegisters||0,0);assert.equal(page.titleInput,'');assert.equal(page.todos.length,0);assert.ok(page.loadError.includes('重新进入'));
});
test('signed-out todo page clears private draft and stale companion labels',async()=>{
 const {page,state}=fixture('TodoTab');page.titleInput='Private';page.noteInput='Secret';page.dueInput='Tomorrow';page.dueAt=200000;page.reminderStatus='Old';page.liveCleanupStatus='Old';state.username='';
 await page.handleReloadTodos();assert.equal(page.titleInput,'');assert.equal(page.noteInput,'');assert.equal(page.dueInput,'');assert.equal(page.dueAt,undefined);assert.equal(page.liveCleanupStatus,'');assert.equal(page.reminderStatus,'登录后查看提醒状态');
});
test('signed-out todo controls never invoke reminder or live view services',async()=>{
 const {page,state}=fixture('TodoTab');state.username='';state.liveCleanupStatus='pending';
 await page.handleReminders();await page.handleDisableReminders();await page.handleRetryLiveCleanup();await page.handleToggle({id:'old'});await page.handleDelete({id:'old'});await page.handleLiveView({id:'old'});
 assert.equal(state.todoRegisters||0,0);assert.equal(state.todoDisabled,undefined);assert.equal(state.liveCleanupStatus,'pending');assert.equal(state.toasts.length,0);assert.ok(page.loadError.includes('登录'));
});
test('todo empty state distinguishes read error from filtered and empty lists',()=>{
 const {page}=fixture('TodoTab');assert.equal(page.emptyTitle(),'暂无待办');page.filter=1;assert.equal(page.emptyTitle(),'暂无未完成任务');page.filter=2;assert.equal(page.emptyTitle(),'暂无已完成任务');page.loadError='failed';assert.equal(page.emptyTitle(),'任务读取未完成');
});
test('todo reminder service late success and failure never report to retired pages',async()=>{
 for(const method of ['handleReminders','handleDisableReminders'])for(const mode of ['disappear','account'])for(const failure of [false,true]){
  const {page,state}=fixture('TodoTab'),pending=gate();state.reminderServicePending=pending.promise;page.reminderStatus='original';const task=page[method]();
  await until(()=>state.todoDisabled||state.todoRegisters);if(mode==='disappear')page.aboutToDisappear();else{state.epoch++;state.username='other'}
  if(failure)pending.reject(Error('fixture service failure'));else pending.resolve();await task;
  assert.equal(state.toasts.length,0);assert.equal(page.reminderStatus,'original');
 }
});
test('todo picker never opens for signed-out or stale account page',async()=>{
 for(const mode of ['signedout','stale']){
  const {page,state}=fixture('TodoTab');await page.aboutToAppear();let opens=0;page.getUIContext=()=>({showDatePickerDialog:()=>opens++});
  state.username=mode==='signedout'?'':'other';state.epoch++;page.chooseDueTime();assert.equal(opens,0);assert.ok(page.loadError.length>0);
 }
});
test('todo native picker callbacks ignore retired pages and accounts',()=>{
 for(const phase of ['date','time'])for(const mode of ['active','disappear','account']){
  const {page,state}=fixture('TodoTab');let dateOptions,timeOptions;
  page.getUIContext=()=>({showDatePickerDialog:o=>dateOptions=o,showTimePickerDialog:o=>timeOptions=o});page.chooseDueTime();
  const retire=()=>{if(mode==='disappear')page.aboutToDisappear();if(mode==='account'){state.epoch++;state.username='other'}};
  if(phase==='date')retire();dateOptions.onAccept({year:2090,month:0,day:2});
  if(phase==='date'&&mode!=='active'){assert.equal(timeOptions,undefined);continue}
  if(phase==='time')retire();timeOptions.onAccept({hour:10,minute:30});assert.equal(page.dueAt!==undefined,mode==='active');
 }
});
test('schedule restoration ignores fractional nonfinite and out-of-term weeks',()=>{
 for(const week of [1.5,NaN,Infinity,-1,0,21,999]){
  const f=fixture('ScheduleTab');f.page.currentWeek=7;f.page.totalWeeks=20;
  f.state.savedUi={selectedWeek:week};f.page.onActivityChange=()=>{};
  f.page.aboutToAppear();assert.equal(f.page.selectedWeek,7);assert.equal(f.page.restoredWeek,0);
 }
 const f=fixture('ScheduleTab');f.state.savedUi={selectedWeek:12};f.page.onActivityChange=()=>{};
 f.page.aboutToAppear();assert.equal(f.page.selectedWeek,12);assert.equal(f.page.restoredWeek,12);
});
test('schedule ignores invalid total weeks instead of truncating or accepting infinity',async()=>{
 for(const totalWeeks of [Infinity,NaN,0,-1,0.5,1.5,61,999]){
  const f=fixture('ScheduleTab');f.page.alive=true;f.page.totalWeeks=20;f.page.updateDerived=()=>{};
  const task=f.page.loadSchedule(false);await until(()=>f.state.requests.length===1);
  f.state.requests[0].resolve({ok:true,data:{courses:[],totalWeeks}});await task;
  assert.equal(f.page.totalWeeks,20);assert.equal(f.page.hasLoaded,true);assert.equal(f.page.errorMsg,'');
 }
});
test('valid semester bounds and alternate field keep selected week inside semester',async()=>{
 for(const [data,expected] of [[{totalWeeks:1},1],[{totalWeeks:60},60],[{totalWeeks:Infinity,weeksTotal:19},19]]){
  const f=fixture('ScheduleTab');f.page.alive=true;f.page.updateDerived=()=>{};
  const task=f.page.loadSchedule(false);await until(()=>f.state.requests.length===1);
  f.state.requests[0].resolve({ok:true,data:{courses:[],...data}});await task;
  assert.equal(f.page.totalWeeks,expected);assert.equal(f.page.hasLoaded,true);
  assert.ok(f.page.selectedWeek>=1&&f.page.selectedWeek<=expected);
 }
});
test('schedule tab handles thrown request and permits retry',async()=>{
 const f=fixture('ScheduleTab'); f.page.alive=true;
 const task=f.page.loadSchedule(false); await until(()=>f.state.requests.length===1);
 f.state.requests[0].reject(Error('transport')); await task;
 assert.equal(f.page.requestBusy,false); assert.equal(f.page.loading,false); assert.ok(f.page.errorMsg);
 const retry=f.page.loadSchedule(false); await until(()=>f.state.requests.length===2);
 f.state.requests[1].resolve({ok:false,error:'fixture error'}); await retry;
 assert.equal(f.page.errorMsg,'fixture error');
});
test('schedule tab preserves loaded courses when forced refresh throws',async()=>{
 const f=fixture('ScheduleTab'); f.page.alive=true; f.page.hasLoaded=true;
 f.page.allCourses=[{title:'fixture course'}];
 const task=f.page.loadSchedule(true); await until(()=>f.state.requests.length===1);
 f.state.requests[0].reject(Error('transport')); await task;
 assert.equal(f.page.allCourses[0].title,'fixture course'); assert.equal(f.page.hasLoaded,true);
 assert.equal(f.page.refreshing,false); assert.equal(f.state.toasts.length,1);
});
test('schedule tab ignores exceptions from a retired account',async()=>{
 const f=fixture('ScheduleTab'); f.page.alive=true; f.page.errorMsg='new account state';
 const task=f.page.loadSchedule(false); await until(()=>f.state.requests.length===1);
 f.state.epoch++; f.state.username='another-account';
 f.state.requests[0].reject(Error('transport')); await task;
 assert.equal(f.page.errorMsg,'new account state'); assert.equal(f.state.toasts.length,0); assert.equal(f.page.requestBusy,false);
});
const queries = [
  ['TransactionsPage', 'transactions', 'items'], ['GradesTab', 'normalGrades', 'grades'], ['ExamsPage', 'exams', 'exams'],
  ['BalancePage', 'accounts', 'accounts'], ['SchedulePage', 'courses', 'courses'],
  ['ProfilePage', 'name', 'name'],
];
function success(key, marker) { return { ok: true, data: { [key]: key === 'name' ? marker : [{ marker }], summary: { weightedGradePoint: 3.8, totalCredits: 6, failedCourseCount: 0 } } }; }
for (const [name, key, field] of queries) {
  test(name + ' keeps successful content on failed refresh and deduplicates taps', async () => {
    const { page, state } = fixture(name); page.alive = true;
    const first = page.load(); state.requests[0].resolve(success(key, 'kept')); await first;
    const kept = page[field], refresh = page.load(true); await page.load(true);
    assert.equal(state.requests.length, 2); assert.equal(state.requests[1].params._forceRefresh, true);
    state.requests[1].resolve({ ok: false, error: 'offline' }); await refresh;
    assert.equal(page.loaded, true); assert.equal(page[field], kept); assert.equal(page.errorMsg, 'offline'); assert.equal(page.loading, false);
  });
  test(name + ' ignores an old response after disappear and resumes loading on reappear', async () => {
    const { page, state } = fixture(name); page.alive = true;
    const old = page.load(); page.aboutToDisappear(); assert.equal(page.loading, false); page.aboutToAppear();
    assert.equal(state.requests.length, 2); state.requests[0].resolve(success(key, 'old')); await old;
    assert.equal(page.loaded, false); assert.equal(page.loading, true);
    state.requests[1].resolve(success(key, 'new')); await until(() => page.loaded);
    assert.equal(field === 'name' ? page[field] : page[field][0].marker, 'new'); assert.equal(page.loading, false);
  });
  test(name + ' rejects responses after logout or account change', async () => {
    for (const change of ['epoch', 'username']) {
      const { page, state } = fixture(name); page.alive = true; const pending = page.load();
      if (change === 'epoch') state.epoch++; else state.username = 'another-student';
      state.requests[0].resolve(success(key, 'old-session')); await pending;
      assert.equal(page.loaded, false); assert.equal(page.loading, false);
    }
  });
  test(name + ' clears busy state on request exception', async () => {
    const { page, state } = fixture(name); page.alive = true; const pending = page.load();
    state.requests[0].reject(new Error('mock offline')); await pending;
    assert.equal(page.loading, false); assert.ok(page.errorMsg.length > 0);
  });
}
test('profile request exception releases busy state and permits retry',async()=>{
 const {page,state}=fixture('ProfileTab'); page.alive=true;
 const first=page.loadProfile(); state.requests[0].reject(new Error('offline')); await first;
 assert.equal(page.requestBusy,false); assert.equal(page.loading,false); assert.ok(page.errorMsg.length>0);
 const second=page.loadProfile(); assert.equal(state.requests.length,2); state.requests[1].resolve({ok:true,data:{name:'fixture'}});await second; assert.equal(page.name,'fixture');
});
test('transaction labels describe the documented rolling 30-day range', () => {
  const source=fs.readFileSync(path.join(root,'entry/src/main/ets/pages/TransactionsPage.ets'),'utf8');
  assert.ok(!source.includes('本月')); assert.ok(source.includes('最近30天'));
});
test('transactions without totalPages continue after full page and stop after short page', async () => {
  const {page,state}=fixture('TransactionsPage'); page.alive=true;
  const first=page.load(); state.requests[0].resolve({ok:true,data:{transactions:Array.from({length:20},(_,i)=>({journo:String(i)})),pageNo:1,pageSize:20}}); await first;
  assert.ok(page.nextPage<=page.totalPages); assert.equal(state.requests[0].params.pageSize,20);
  const second=page.load(false,true); assert.equal(state.requests[1].params.pageNo,2); state.requests[1].resolve({ok:true,data:{transactions:[{journo:'last'}],pageNo:2,pageSize:20}}); await second;
  assert.equal(page.items.length,21); assert.ok(page.nextPage>page.totalPages);
});
test('grade summary does not present missing or nonfinite values as zero', async () => {
  const { page, state } = fixture('GradesTab'); page.alive = true; const pending = page.load();
  state.requests[0].resolve({ ok: true, data: { normalGrades: [], summary: { weightedGradePoint: NaN, totalCredits: Infinity } } }); await pending;
  assert.equal(page.gpa, '—'); assert.equal(page.credits, '—'); assert.equal(page.failedCount, '—');
});
test('recharge configuration retry resets unavailable selected options', async () => {
  const { page, state } = fixture('RechargePage'); page.alive = true; page.selectedAmount = '100'; page.selectedPayCode = 'old';
  const pending = page.loadConfig(true); state.requests[0].resolve({ ok: true, data: { balance: '12.00', amountOptions: [{ id: '1', amount: '50', name: '50元' }], payMethods: [{ code: '06', name: '示例' }] } }); await pending;
  assert.equal(page.loading, false); assert.equal(page.selectedAmount, ''); assert.equal(page.selectedPayCode, '');
});
test('recharge prefers official transfer link over h5 and keeps a fallback', async () => {
  const official = fixture('RechargePage'); official.page.alive = true; official.page.loading = false;
  official.page.selectedAmount = '50'; official.page.selectedPayCode = '06';
  const pending = official.page.handlePay();
  official.state.requests[0].resolve({ ok: true, data: { payResult: { h5Url: 'https://h5.invalid', officialTransferUrl: 'https://transfer.invalid' } } });
  await pending;
  assert.equal(official.page.step, 3); assert.equal(official.page.payContentType, 'url');
  assert.equal(official.page.payContent, 'https://transfer.invalid');

  const fallback = fixture('RechargePage'); fallback.page.alive = true; fallback.page.loading = false;
  fallback.page.selectedAmount = '50'; fallback.page.selectedPayCode = '06';
  const second = fallback.page.handlePay();
  fallback.state.requests[0].resolve({ ok: true, data: { payResult: { officialTransferUrl: '', h5Url: 'https://h5.invalid' } } });
  await second;
  assert.equal(fallback.page.step, 3); assert.equal(fallback.page.payContent, 'https://h5.invalid');

  const empty = fixture('RechargePage'); empty.page.alive = true; empty.page.loading = false;
  empty.page.selectedAmount = '50'; empty.page.selectedPayCode = '06';
  const third = empty.page.handlePay();
  empty.state.requests[0].resolve({ ok: true, data: { payResult: {} } });
  await third;
  assert.equal(empty.page.step, 1); assert.equal(empty.page.payContent, '');
  assert.ok(empty.state.toasts.at(-1).includes('一卡通'));
});
test('recharge explicit payment deduplicates and rejects late account results', async () => {
  const { page, state } = fixture('RechargePage'); page.alive = true; page.loading = false; page.selectedAmount = '50'; page.selectedPayCode = '06';
  const pending = page.handlePay(); await page.handlePay(); assert.equal(state.requests.length, 1); state.epoch++;
  state.requests[0].resolve({ ok: true, data: { payResult: { h5Url: 'https://mock.invalid' } } }); await pending;
  assert.equal(page.step, 1); assert.equal(page.payContent, ''); assert.equal(page.paying, false);
});
test('electricity back prevents a late query from advancing the step', async () => {
  const { page, state } = fixture('ElectricityPage'); page.alive = true; page.roomQuery = ' 1-101 ';
  const pending = page.queryElectricity(); assert.equal(state.requests[0].params.roomQuery, '1-101'); page.back();
  state.requests[0].resolve({ ok: true, data: { marker: 'old' } }); await pending;
  assert.equal(page.step, 1); assert.equal(page.electricity, null); assert.equal(page.loading, false);
});
test('electricity payment cannot submit twice or navigate to a duplicate order', async () => {
  const { page, state } = fixture('ElectricityPage'); page.alive = true; page.step = 3; page.selectedAmount = '50';
  const pending = page.handlePay(); await page.handlePay(); page.back();
  assert.equal(state.requests.length, 1); assert.equal(page.step, 3);
  state.requests[0].resolve({ ok: false, error: 'offline' }); await pending;
  assert.equal(page.paying, false); assert.equal(page.errorMsg, 'offline');
});
test('QR background stops timers and clears expired code before resumed request', async () => {
  const { page, state } = fixture('QRCodePage'); page.alive = true;
  const pending = page.fetchCode(); state.requests[0].resolve({ ok: true, data: { qrcode: 'sample-only', expiresInSeconds: 30 } }); await pending;
  assert.equal(state.timers.size, 2); page.appActive = false; page.onAppActiveChange(); assert.equal(state.timers.size, 0);
  await page.fetchCode(); assert.equal(state.requests.length, 1); state.now += 31000;
  page.appActive = true; page.onAppActiveChange(); assert.equal(page.qrcode, ''); assert.equal(state.requests.length, 2);
  state.requests[1].resolve({ ok: false, error: 'offline' }); await until(() => !page.requestBusy);
  assert.equal(state.timers.size, 0); assert.equal(page.qrcode, '');
});
test('QR response while hidden cannot restart timers', async () => {
  const { page, state } = fixture('QRCodePage'); page.alive = true;
  const pending = page.fetchCode(); page.onPageHide(); state.requests[0].resolve({ ok: true, data: { qrcode: 'sample-only', expiresInSeconds: 30 } }); await pending;
  assert.equal(state.timers.size, 0); assert.equal(page.loading, false);
});
test('QR expiry interval removes a stale code even when refresh fails', async () => {
  const { page, state } = fixture('QRCodePage'); page.alive = true;
  const pending = page.fetchCode(); state.requests[0].resolve({ ok: true, data: { qrcode: 'sample-only', expiresInSeconds: 1 } }); await pending;
  state.now += 1100; [...state.timers.values()].find(t => t.interval).fn(); assert.equal(page.qrcode, ''); assert.equal(page.countdown, 0);
});
test('QR request exception clears loading and offers an error state', async () => {
  const { page, state } = fixture('QRCodePage'); page.alive = true;
  const pending = page.fetchCode(); state.requests[0].reject(new Error('offline')); await pending;
  assert.equal(page.loading, false); assert.equal(page.requestBusy, false); assert.ok(page.errorMsg.length > 0); assert.equal(state.timers.size, 0);
});

test('native transactions append successive school pages without duplicate requests', async () => {
  const {page,state}=fixture('TransactionsPage'); page.alive=true;
  let pending=page.load(); assert.equal(state.requests[0].params.pageNo,1);
  state.requests[0].resolve({ok:true,data:{transactions:[{journo:'one'}],pageNo:1,totalPages:3}}); await pending;
  pending=page.load(false,true); await page.load(false,true);
  assert.equal(state.requests.length,2); assert.equal(state.requests[1].params.pageNo,2);
  state.requests[1].resolve({ok:true,data:{transactions:[{journo:'two'}],pageNo:2,totalPages:3}}); await pending;
  assert.deepEqual(Array.from(page.items,x=>x.journo),['one','two']); assert.equal(page.nextPage,3);
  pending=page.load(false,true); assert.equal(state.requests[2].params.pageNo,3);
  state.requests[2].resolve({ok:true,data:{transactions:[{journo:'three'}],pageNo:3,totalPages:3}}); await pending;
  assert.equal(page.items.length,3); assert.equal(page.nextPage,4); assert.equal(page.rows.totalCount(),3);
});
test('native transactions retry a failed page and replace rows on refresh', async () => {
  const {page,state}=fixture('TransactionsPage'); page.alive=true;
  let pending=page.load(); state.requests[0].resolve({ok:true,data:{transactions:[{journo:'old'}],pageNo:1,totalPages:2}}); await pending;
  pending=page.load(false,true); state.requests[1].resolve({ok:false,error:'page unavailable'}); await pending;
  assert.equal(page.items.length,1); assert.equal(page.nextPage,2); assert.equal(page.loaded,true);
  pending=page.load(false,true); assert.equal(state.requests[2].params.pageNo,2);
  state.requests[2].resolve({ok:true,data:{transactions:[{journo:'second'}],pageNo:2,totalPages:2}}); await pending;
  pending=page.load(true); assert.equal(state.requests[3].params.pageNo,1);
  state.requests[3].resolve({ok:true,data:{transactions:[{journo:'new'}],pageNo:1,totalPages:1}}); await pending;
  assert.deepEqual(Array.from(page.items,x=>x.journo),['new']); assert.equal(page.nextPage,2); assert.equal(page.totalPages,1);
});
for(const [name,key,field] of [['BalancePage','accounts','accounts'],['TransactionsPage','transactions','items']]) {
  test(name+' rejects a late result when only the card session changes',async()=>{
    const {page,state}=fixture(name); page.alive=true;
    let pending=page.load(); state.requests[0].resolve(success(key,'old card')); await pending;
    pending=page.load(true); state.cardEpoch++;
    state.requests[1].resolve(success(key,'retired card')); await pending;
    assert.equal(page.loaded,false); assert.equal(page[field].length,0); assert.equal(page.cardAccount,''); assert.equal(page.errorMsg,''); assert.equal(page.loading,false);
    pending=page.load(); state.requests[2].resolve(success(key,'current card')); await pending;
    assert.equal(page.loaded,true); assert.equal(page[field][0].marker,'current card');
  });
  test(name+' ignores a request exception from a retired card session',async()=>{
    const {page,state}=fixture(name); page.alive=true;
    const pending=page.load(); state.cardEpoch++; state.requests[0].reject(new Error('retired request')); await pending;
    assert.equal(page.loaded,false); assert.equal(page[field].length,0); assert.equal(page.errorMsg,''); assert.equal(page.loading,false);
  });
}

// 充值页进入收银台是页面内切屏，不是路由跳转，所以要用组件级 transition 表达方向感。
// 硬切会让用户在输密码前不知道界面换了；而随意加动画又容易在"减少动效"下留下残余位移。
test('checkout slides in from the right and stalls under reduced motion', () => {
  const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/RechargePage.ets'), 'utf8');
  // 收银台（Web）进场：右移 72 淡入；出场只淡出，避免和金额页出场抢。
  assert.match(source, /TransitionEffect\.OPACITY\.combine\(TransitionEffect\.translate\(\{ x: 72 \}\)\)/);
  assert.match(source, /TransitionEffect\.asymmetric\(/);
  assert.match(source, /curve: Motion\.curve\.decelerate/);
  assert.match(source, /curve: Motion\.curve\.accelerate/);
  // 金额页退场：轻微缩小 + 淡出，给收银台留出层次。
  assert.match(source, /TransitionEffect\.OPACITY\.combine\(TransitionEffect\.scale\(\{ x: 0\.97, y: 0\.97 \}\)\)/);
  // 所有时长都必须走 motionDuration()，它是"减少动效"的唯一开关：
  // 直接把数字写进 animation 会在偏好开启时仍然播动画。
  const durs = [...source.matchAll(/animation\(\{ duration: ([^,]+),/g)].map(m => m[1].trim());
  assert.ok(durs.length >= 3, 'the page must declare its transition durations');
  assert.ok(durs.every(d => d.startsWith('motionDuration(')), 'every transition duration must go through motionDuration(): ' + durs.join(' | '));
});

(async () => {
  let failed = 0;
  for (const t of tests) { try { await t.run(); console.log('PASS ' + t.name); } catch (error) { failed++; console.error('FAIL ' + t.name); console.error(error.stack); } }
  console.log(tests.length + ' page behavior checks, ' + failed + ' failed'); process.exitCode = failed ? 1 : 0;
})();
