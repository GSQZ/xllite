'use strict';
// Repeatable service regression checks. Runs actual .ets service code with mocked
// HarmonyOS preferences/HTTP; no credentials, network, installs or device needed.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const tsPath = process.env.XJIT_TYPESCRIPT_PATH || 'D:/data/devecostudionext/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js';
if (!fs.existsSync(tsPath)) throw new Error('Existing SDK TypeScript not found. Set XJIT_TYPESCRIPT_PATH; no download is attempted.');
const ts = require(tsPath);
const crypto = require('node:crypto');
function schoolJwt(exp = Math.floor(Date.now() / 1000) + 3600) { return Buffer.from('{}').toString('base64url') + '.' + Buffer.from(JSON.stringify({exp})).toString('base64url') + '.fixture'; }
function schoolResponse(request) {
  const data = request.url.includes('/personal/me/user') ? {code:0,data:{attributes:{accountId:'student',userName:'测试同学',organizationName:'测试学院'}}} :
    request.url.endsWith('/user/info') ? {success:true,resultData:{user:{balance:'12.34',username:'校园卡测试用户',idSerial:'fixture-card'}}} :
    {success:true,resultData:{rows:[{txdate:'2026-10-09 12:00:00',mername:'测试商户',txamt:'650'}],totalpage:1}};
  return {responseCode:200,result:JSON.stringify(data)};
}
const tests = [];
function test(name, run) { tests.push({ name, run }); }
function deferred() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }
async function until(predicate) {
  for (let i = 0; i < 500; i++) { if (predicate()) return; await Promise.resolve(); }
  throw new Error('Expected asynchronous checkpoint was not reached');
}
function fixture(sharedStores = new Map()) {
  const stores = sharedStores, opens = new Map(), modules = new Map();
  const timers = new Map(); let nextTimer = 1;
  const state = { requests: [], created: 0, destroyed: 0, active: 0, peak: 0, appActive: true, mainPageActive: true, hook: null, respond: null };
  function prefs(name) {
    if (!stores.has(name)) {
      const fresh = { data: new Map(), flushes: 0, reads: 0, writes: 0 };
      // 待办存储一建出来就带上当前账号的归属标记。真实流程里 AuthManager 先登录
      // 再写待办，磁盘上不可能出现「有 items 没有 owner」的组合；测试直接在磁盘
      // 预置数据时若漏了 owner，会被判成别的账号的数据而丢弃，掩盖真正的行为。
      if (name === 'xjit_todos') fresh.data.set('owner', 'p4d75g-efo4lw');
      stores.set(name, fresh);
    }
    const store = stores.get(name);
    return {
      async get(key, fallback) { store.reads++; const value = store.data.has(key) ? store.data.get(key) : fallback; if (state.hook) await state.hook(name, 'get', key); return value; },
      async put(key, value) { store.writes++; if (state.hook) await state.hook(name, 'put', key); store.data.set(key, value); },
      async delete(key) { if (state.hook) await state.hook(name, 'delete', key); store.data.delete(key); },
      async clear() { if (state.hook) await state.hook(name, 'clear'); store.data.clear(); },
      async flush() { store.flushes++; if (state.hook) await state.hook(name, 'flush'); store.durable = new Map(store.data); },
    };
  }
  const preferences = { async getPreferences(_ctx, name) { opens.set(name, (opens.get(name) || 0) + 1); return prefs(name); } };
  const http = { RequestMethod: { GET: 'GET', POST: 'POST' }, createHttp() {
    state.created++; let destroyed = false;
    return {
      async request(url, options) {
        const body = options.extraData ? JSON.parse(options.extraData) : {};
        const request = { url, options, body }; state.requests.push(request); state.active++; state.peak = Math.max(state.peak, state.active);
        try {
          if (state.respond) return await state.respond(request);
          return schoolResponse(request);
        } finally { state.active--; }
      },
      destroy() { assert.equal(destroyed, false, 'HTTP session destroyed twice'); destroyed = true; state.destroyed++; },
    };
  } };
  function load(filename) {
    const full = path.resolve(root, filename);
    if (modules.has(full)) return modules.get(full).exports;
    const module = { exports: {} }; modules.set(full, module);
    const source = fs.readFileSync(full, 'utf8');
    const output = ts.transpileModule(source, { fileName: full.replace(/\.ets$/, '.ts'), compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
    const localRequire = spec => {
      if (spec === './LiveViewService' && full.endsWith('TodoService.ets')) return {async reconcileTodoLiveView(items){state.liveTodoItems=items;if(state.liveTodoPending)await state.liveTodoPending;if(state.liveTodoFailure)throw Error('fixture live failure')}};
      if (spec === './TodoReminderService') return {async getTodoReminderCount(){if(state.todoCountFailure)throw Error('fixture count failure');return state.todoNativeCount||0},async syncTodoReminders(items,bundle){state.todoSync={items,bundle};if(state.todoSyncPending)await state.todoSyncPending;if(state.todoSyncFailure)throw Error('fixture sync failure');return items.length},async clearTodoReminders(){state.todoReminderClears=(state.todoReminderClears||0)+1;if(state.todoClearPending)await state.todoClearPending;if(state.todoClearFailure)throw Error('fixture clear failure');}};
      if (spec === './WidgetService') return {async publishTodoWidgets(_ctx,data){state.todoWidgets=(state.todoWidgets||[]);state.todoWidgets.push(data);if(state.todoWidgetPending)await state.todoWidgetPending;if(state.todoWidgetFailure)throw new Error('fixture widget failure')}};
      if (spec === './CampusCompanionService' && full.endsWith('AuthManager.ets')) return {async clearCampusCompanion(){state.companionClears=(state.companionClears||0)+1;if(state.companionClearFailure)throw Error('fixture companion cleanup failed')}};
      if (spec === '@ohos.data.preferences') return { default: preferences };
      if (spec === '@ohos.net.http') return { default: http };
      // Logger 封装会按级别分派，缺任一方法都会让服务层一打日志就抛 TypeError。
      if (spec === '@ohos.hilog') return { default: { debug() {}, info() {}, warn() {}, error() {} } };
      if (spec === '@ohos.app.ability.ConfigurationConstant') return {default:{ColorMode:{COLOR_MODE_DARK:0,COLOR_MODE_LIGHT:1,COLOR_MODE_NOT_SET:-1}}};
      if (spec === '@ohos.util') return { default: { TextEncoder: class extends TextEncoder {encodeInto(s) {return this.encode(s);}}, TextDecoder: class extends TextDecoder { decodeToString(b) { return this.decode(b); } }, Base64Helper: class {decodeSync(s) {return new Uint8Array(Buffer.from(s,'base64'));}} } };
      if (spec === '@ohos.security.cryptoFramework') return { default: {
        CryptoMode:{DECRYPT_MODE:0},createSymKeyGenerator(algorithm) {assert.equal(algorithm,'SM4_128');return {async convertKey(key){return key;}};},
        createCipher(algorithm) {assert.equal(algorithm,'SM4_128|ECB|PKCS7');let key;return {async init(mode,k,iv){assert.equal(mode,0);assert.equal(iv,null);key=k;},
          async doFinal(input){const c=crypto.createDecipheriv('sm4-ecb',Buffer.from(key.data),null);return {data:new Uint8Array(Buffer.concat([c.update(Buffer.from(input.data)),c.final()]))};}};}
      } };
      if (spec === '@ohos.web.webview') return {default:{WebCookieManager:{clearAllCookiesSync(privateStore){assert.equal(privateStore,true);state.cookieClears=(state.cookieClears||0)+1;}},WebStorage:{deleteAllData(privateStore){assert.equal(privateStore,true);state.storageClears=(state.storageClears||0)+1;}}}};
      if (spec.startsWith('@ohos.') || spec.startsWith('@kit.')) return { default: {} };
      return load(path.relative(root, path.resolve(path.dirname(full), spec + '.ets')));
    };
    const context = vm.createContext({ exports: module.exports, module, require: localRequire, console, Date, Map, Promise,
      AppStorage: { get: key => state[key], set: (key, value) => { state[key] = value; return true; }, setOrCreate: (key, value) => { state[key] = value; return true; } },
      setTimeout: fn => { const id = nextTimer++; timers.set(id, fn); return id; }, clearTimeout: id => timers.delete(id),
    });
    vm.runInContext(output, context, { filename: full });
    return module.exports;
  }
  const cache = load('entry/src/main/ets/services/MemoryCache.ets');
  const auth = load('entry/src/main/ets/services/AuthManager.ets');
  auth.setAuthContext({});
  const api = load('entry/src/main/ets/services/ApiService.ets');
 const todo = load('entry/src/main/ets/services/TodoService.ets'); todo.setTodoContext({});
 // 真实调用顺序里 AuthManager 一定先设好归属再有页面读待办。默认给一个已登录账号，
 // 否则归属标记为空串，和磁盘上缺失的 owner 相等会被判成同一账号，测试就掩盖了这个问题。
 todo.setTodoOwner('fixture-student');
  const theme = load('entry/src/main/ets/services/ThemeService.ets');
  return { cache, auth, api, todo, theme, state, stores, opens, timers, prefs, load,
    async seedToken() { await auth.saveSchoolSession('student', schoolJwt(), Date.now()+3600000); auth.saveCardToken('fixture-card-token',Date.now()+3600000,cache.getCacheEpoch()); },
    async runTimers() { const callbacks = [...timers.values()]; timers.clear(); callbacks.forEach(fn => fn()); await until(() => stores.get('xjit_http_cache')?.flushes > 0); },
  };
}
test('persisted cleanup marker blocks old todo data in a fresh process and permits explicit clearing',async()=>{
 const f=fixture();await f.todo.addTodo({title:'Private old',note:'',dueText:''});await f.prefs('xjit_todos').put('cleanup_pending',true);
 const restarted=fixture(f.stores);await assert.rejects(restarted.todo.loadTodos(),/清理/);await assert.rejects(restarted.todo.addTodo({title:'New',note:'',dueText:''}),/清理/);
 await restarted.todo.clearTodos();assert.equal(restarted.stores.get('xjit_todos').data.get('cleanup_pending'),false);assert.equal((await fixture(f.stores).todo.loadTodos()).length,0);
});
test('actual failed cleanup persists marker before task deletion and survives service restart',async()=>{
 const f=fixture();await f.todo.addTodo({title:'Private old',note:'',dueText:''});const before=f.stores.get('xjit_todos').data.get('items');
 f.state.hook=async(name,op,key)=>{if(name==='xjit_todos'&&op==='put'&&key==='items')throw Error('fixture task deletion failed')};
 await assert.rejects(f.todo.clearTodos(),/task deletion failed/);assert.equal(f.stores.get('xjit_todos').data.get('items'),before);assert.equal(f.stores.get('xjit_todos').data.get('cleanup_pending'),true);
 const restarted=fixture(f.stores);await assert.rejects(restarted.todo.loadTodos(),/清理/);await restarted.todo.clearTodos();assert.equal((await fixture(f.stores).todo.loadTodos()).length,0);
});
test('cleanup crash recovery uses last successful flush rather than unflushed memory',async()=>{
 const f=fixture();await f.todo.addTodo({title:'Private durable',note:'',dueText:''});const store=f.stores.get('xjit_todos');let flushes=0;
 f.state.hook=async(name,op)=>{if(name==='xjit_todos'&&op==='flush'&&++flushes===2)throw Error('fixture task flush failed')};
 await assert.rejects(f.todo.clearTodos(),/task flush failed/);assert.equal(store.durable.get('cleanup_pending'),true);assert.ok(store.durable.get('items').includes('Private durable'));
 const disk=new Map([['xjit_todos',{data:new Map(store.durable),flushes:0,reads:0,writes:0}]]),restarted=fixture(disk);
 await assert.rejects(restarted.todo.loadTodos(),/清理/);await restarted.todo.clearTodos();const saved=disk.get('xjit_todos').durable;assert.equal(saved.get('cleanup_pending'),false);assert.equal(saved.get('items'),'[]');
});
test('logout failure waits for other cleanup branches before allowing retry',async()=>{
 const f=fixture(),gate=deferred();await f.seedToken();await f.todo.addTodo({title:'Private',note:'',dueText:''});f.state.companionClearFailure=true;let entered=false,settled=false;
 f.state.hook=async(name,op)=>{if(name==='xjit_todos'&&op==='put'){entered=true;await gate.promise}};
 const logout=f.auth.clearSession().then(()=>{settled=true},()=>{settled=true});await until(()=>entered);for(let i=0;i<20;i++)await Promise.resolve();assert.equal(settled,false);
 gate.resolve();await logout;assert.equal(settled,true);assert.equal(f.stores.get('xjit_todos').data.get('items'),'[]');
});
test('logout reports companion cleanup failure while still clearing private task and auth state',async()=>{
 const f=fixture();await f.seedToken();await f.todo.addTodo({title:'Private',note:'',dueText:''});f.state.companionClearFailure=true;
 await assert.rejects(f.auth.clearSession(),/companion cleanup failed/);await until(()=>f.stores.get('xjit_todos').data.get('items')==='[]');assert.equal(f.auth.getUsername(),'');assert.equal(f.auth.getAccessToken(),'');assert.ok(f.state.todoReminderClears>0);
 f.state.companionClearFailure=false;await f.auth.clearSession();assert.equal(f.state.companionClears,2);
});
test('todo read started before logout never returns the retired private rows',async()=>{
 const f=fixture(),gate=deferred();await f.prefs('xjit_todos').put('items',JSON.stringify([{id:'old',title:'Private',note:'',dueText:'',done:false,createdAt:1,updatedAt:1}]));let started=false;
 f.state.hook=async(name,op)=>{if(name==='xjit_todos'&&op==='get'){started=true;await gate.promise}};
 const read=f.todo.loadTodos().then(rows=>rows,()=>[]),observed=read.then(rows=>assert.equal(rows.length,0,'a retired read must not return private rows'));await until(()=>started);const clear=f.todo.clearTodos();gate.resolve();await Promise.all([observed,clear]);assert.equal((await f.todo.loadTodos()).length,0);
});
test('todo flush failure preserves committed memory and blocks failed logout cleanup',async()=>{
 const f=fixture();await f.todo.addTodo({title:'Committed',note:'',dueText:''});const widgets=f.state.todoWidgets.length;
 f.state.hook=async(name,op)=>{if(name==='xjit_todos'&&op==='flush')throw Error('fixture flush failure')};
 await assert.rejects(f.todo.addTodo({title:'Uncommitted',note:'',dueText:''}),/flush failure/);assert.equal((await f.todo.loadTodos()).length,1);assert.equal(f.state.todoWidgets.length,widgets);
 await assert.rejects(f.todo.clearTodos(),/flush failure/);await assert.rejects(f.todo.loadTodos(),/清理/);f.state.hook=null;await f.todo.clearTodos();assert.equal((await f.todo.loadTodos()).length,0);
});
test('failed logout clearing blocks old todo cache until explicit cleanup retry succeeds',async()=>{
 const f=fixture();await f.todo.addTodo({title:'Private old task',note:'',dueText:''});
 f.state.hook=async(name,op)=>{if(name==='xjit_todos'&&op==='put')throw Error('fixture clear failure')};await assert.rejects(f.todo.clearTodos());
 await assert.rejects(f.todo.loadTodos(),/清理/);await assert.rejects(f.todo.addTodo({title:'New account',note:'',dueText:''}),/清理/);
 f.state.hook=null;await f.todo.clearTodos();assert.equal((await f.todo.loadTodos()).length,0);
});
test('a different account never inherits tasks left by a failed logout cleanup',async()=>{
 const f=fixture();f.todo.setTodoContext({abilityInfo:{bundleName:'com.xjit.app.acceptance'}});
 await f.auth.saveSchoolSession('alice','token-alice',Date.now()+3600000);
 await f.todo.addTodo({title:'Alice private',note:'',dueText:''});
 f.state.hook=async(name,op,key)=>{if(name===TODOS&&op==='put'&&key==='items')throw Error('fixture deletion failed')};
 await assert.rejects(f.auth.clearSession(),/deletion failed/);
 assert.ok(f.stores.get(TODOS).data.get('items').includes('Alice private'));
 f.state.hook=null;
 const bob=fixture(f.stores);await bob.auth.saveSchoolSession('bob','token-bob',Date.now()+3600000);
 assert.equal((await bob.todo.loadTodos()).length,0);
 const aliceAgain=fixture(f.stores);await aliceAgain.auth.saveSchoolSession('alice','token-alice-2',Date.now()+3600000);
 assert.equal((await aliceAgain.todo.loadTodos()).length,0);
});
test('todo read failure blocks mutation without overwriting existing tasks and allows retry',async()=>{
 const f=fixture();f.todo.setTodoContext({abilityInfo:{bundleName:'com.xjit.app.acceptance'}});const original=JSON.stringify([{id:'old',title:'Existing',note:'',dueText:'',done:false,createdAt:1,updatedAt:1}]);await f.prefs('xjit_todos').put('items',original);
 f.state.hook=async(name,op)=>{if(name==='xjit_todos'&&op==='get')throw Error('fixture read failure')};
 await assert.rejects(f.todo.addTodo({title:'New',note:'',dueText:''}),/read failure/);assert.equal(f.stores.get('xjit_todos').data.get('items'),original);
 f.state.hook=null;assert.equal((await f.todo.loadTodos())[0].title,'Existing');
});
test('saved todo changes reconcile live view even when system stop fails',async()=>{
 const f=fixture();f.todo.setTodoContext({abilityInfo:{bundleName:'com.xjit.app.acceptance'}});const rows=await f.todo.addTodo({title:'Study',note:'',dueText:''});
 f.state.liveTodoFailure=true;const changed=await f.todo.toggleTodo(rows[0].id);assert.equal(changed[0].done,true);assert.equal(f.state.liveTodoItems[0].done,true);
 await f.todo.deleteTodo(rows[0].id);assert.equal(f.state.liveTodoItems.length,0);
 assert.ok(f.todo.getTodoLiveCleanupStatus().includes('未完成'));
 f.state.liveTodoFailure=false;await f.todo.retryTodoLiveCleanup();assert.equal(f.todo.getTodoLiveCleanupStatus(),'');
});
test('todo restored reminder status reflects native count without enabling automatic sync',async()=>{
 const f=fixture();f.state.todoNativeCount=3;await f.todo.restoreTodoReminderStatus();assert.ok(f.todo.getTodoReminderStatus().includes('3'));assert.ok(f.todo.getTodoReminderStatus().includes('未开启'));
 await f.todo.addTodo({title:'Study',note:'',dueText:''});assert.equal(f.state.todoSync,undefined);
 f.state.todoCountFailure=true;await f.todo.restoreTodoReminderStatus();assert.ok(f.todo.getTodoReminderStatus().includes('状态未知'));
});
test('retired reminder registration never returns a success count',async()=>{
 const f=fixture(),gate=deferred();f.todo.setTodoContext({abilityInfo:{bundleName:'com.xjit.app.acceptance'}});f.state.todoSyncPending=gate.promise;
 const register=f.todo.registerTodoReminders(),observed=assert.rejects(register,/会话/);await until(()=>!!f.state.todoSync);
 const clear=f.todo.clearTodos();gate.resolve();await Promise.all([observed,clear]);assert.equal(f.todo.getTodoReminderStatus(),'尚未登记任务提醒');
});
test('retired reminder cancellation cannot overwrite new session status',async()=>{
 for(const failure of [false,true]){
  const f=fixture(),gate=deferred();f.state.todoClearPending=gate.promise;f.state.todoClearFailure=failure;
  const disable=f.todo.disableTodoReminders();const observed=disable.catch(()=>{});await until(()=>f.state.todoReminderClears===1);
  const clear=f.todo.clearTodos();gate.resolve();await Promise.all([observed,clear]);assert.equal(f.todo.getTodoReminderStatus(),'尚未登记任务提醒');
 }
});
test('explicit reminder failures replace stale success status',async()=>{
 const f=fixture();f.todo.setTodoContext({abilityInfo:{bundleName:'com.xjit.app.acceptance'}});await f.todo.registerTodoReminders();
 f.state.todoSyncFailure=true;await assert.rejects(f.todo.registerTodoReminders());assert.ok(f.todo.getTodoReminderStatus().includes('登记未完成'));
 f.state.todoClearFailure=true;await assert.rejects(f.todo.disableTodoReminders());assert.ok(f.todo.getTodoReminderStatus().includes('取消未完成'));
});
test('todo reminder failure state is visible while saved task change remains committed',async()=>{
 const f=fixture();f.todo.setTodoContext({abilityInfo:{bundleName:'com.xjit.app.acceptance'}});const rows=await f.todo.addTodo({title:'Study',note:'',dueText:''});
 await f.todo.registerTodoReminders();assert.ok(f.todo.getTodoReminderStatus().includes('1'));
 f.state.todoSyncFailure=true;const changed=await f.todo.toggleTodo(rows[0].id);assert.equal(changed[0].done,true);assert.ok(f.todo.getTodoReminderStatus().includes('未同步'));
 f.state.todoSyncFailure=false;await f.todo.registerTodoReminders();assert.ok(!f.todo.getTodoReminderStatus().includes('未同步'));
});
test('todo reminder opt-out cancels system group and preserves tasks without later auto sync',async()=>{
 const f=fixture();f.todo.setTodoContext({abilityInfo:{bundleName:'com.xjit.app.acceptance'}});const rows=await f.todo.addTodo({title:'Study',note:'',dueText:''});
 await f.todo.registerTodoReminders();await f.todo.disableTodoReminders();assert.equal(f.state.todoReminderClears,1);assert.equal((await f.todo.loadTodos()).length,1);
 f.state.todoSync=undefined;await f.todo.toggleTodo(rows[0].id);assert.equal(f.state.todoSync,undefined);
});
test('todo explicit reminder request uses initialized bundle and persisted tasks',async()=>{
 const f=fixture();f.todo.setTodoContext({abilityInfo:{bundleName:'com.xjit.app.acceptance'}});await f.todo.addTodo({title:'Study',note:'',dueText:''});
 assert.equal(await f.todo.registerTodoReminders(),1);assert.equal(f.state.todoSync.bundle,'com.xjit.app.acceptance');assert.equal(f.state.todoSync.items[0].title,'Study');
});
test('todo changes resynchronize reminders only after explicit successful registration',async()=>{
 const f=fixture();f.todo.setTodoContext({abilityInfo:{bundleName:'com.xjit.app.acceptance'}});
 const rows=await f.todo.addTodo({title:'Study',note:'',dueText:''});assert.equal(f.state.todoSync,undefined);
 await f.todo.registerTodoReminders();await f.todo.toggleTodo(rows[0].id);assert.equal(f.state.todoSync.items[0].done,true);
 await f.todo.deleteTodo(rows[0].id);assert.equal(f.state.todoSync.items.length,0);
 await f.todo.clearTodos();f.state.todoSync=undefined;await f.todo.addTodo({title:'New',note:'',dueText:''});assert.equal(f.state.todoSync,undefined);
});
test('logout starts reminder cleanup even when todo disk cleanup fails',async()=>{
 const f=fixture();await f.seedToken();f.state.hook=async(name,op)=>{if(name==='xjit_todos'&&op==='put')throw Error('fixture todo clear failure')};
 await assert.rejects(f.auth.clearSession(),/todo clear failure/);assert.equal(f.state.todoReminderClears,1);assert.equal(f.auth.getUsername(),'');
});
test('todo reminder plans exclude inactive tasks and never round delivery earlier',()=>{
 const f=fixture(),plan=f.load('entry/src/main/ets/utils/TodoReminderPlan.ets').buildTodoReminderPlans;
 const item=(id,dueAt,done=false)=>({id,title:id,note:'',dueText:'',dueAt,done,createdAt:1,updatedAt:1});
 const rows=plan([item('later',180001),item('past',500),item('done',120000,true),item('untimed'),item('first',120000)],1000);
 assert.equal(rows.length,2);assert.equal(rows[0].taskId,'first');assert.equal(rows[0].triggerAt,120000);assert.equal(rows[1].triggerAt,240000);assert.equal(rows[0].route,'todo');
});
test('todo restored disk tasks refresh card without a task mutation',async()=>{
 const f=fixture();await f.prefs('xjit_todos').put('items',JSON.stringify([{id:'restored',title:'Restored',note:'',dueText:'',done:false,createdAt:1,updatedAt:1}]));
 await f.todo.refreshTodoWidgets();assert.equal(f.state.todoWidgets.at(-1).firstTitle,'Restored');
 assert.equal(f.stores.get('xjit_todos').writes,1);
});
test('logout retires add paused before mutation enqueue',async()=>{
 const f=fixture(),gate=deferred();let entered=false;
 f.state.hook=async(name,op)=>{if(name==='xjit_todos'&&op==='get'){entered=true;await gate.promise}};
 const add=f.todo.addTodo({title:'Old account',note:'',dueText:''});const retired=assert.rejects(add,/会话/);
 await until(()=>entered);const clear=f.todo.clearTodos();gate.resolve();await Promise.all([retired,clear]);
 assert.equal((await f.todo.loadTodos()).length,0);assert.equal(f.state.todoWidgets.at(-1).openCount,0);
});
test('logout during widget refresh never returns retired private task result',async()=>{
 const f=fixture(),gate=deferred();f.state.todoWidgetPending=gate.promise;
 const add=f.todo.addTodo({title:'Private retired',note:'',dueText:''}),observed=assert.rejects(add,/会话/);await until(()=>!!f.state.todoWidgets);
 const clear=f.todo.clearTodos();gate.resolve();await Promise.all([observed,clear]);assert.equal((await f.todo.loadTodos()).length,0);assert.equal(f.state.todoWidgets.at(-1).openCount,0);
});
test('logout during live cleanup skips retired widget publication',async()=>{
 const f=fixture(),gate=deferred();f.state.liveTodoPending=gate.promise;
 const add=f.todo.addTodo({title:'Private retired',note:'',dueText:''}),observed=assert.rejects(add,/会话/);await until(()=>!!f.state.liveTodoItems);
 const clear=f.todo.clearTodos();gate.resolve();await Promise.all([observed,clear]);assert.equal(f.state.todoWidgets.length,1);assert.equal(f.state.todoWidgets[0].openCount,0);
});
test('todo write finishing after logout never publishes retired private task data',async()=>{
 const f=fixture(),gate=deferred();let started=false;f.state.hook=async(name,op)=>{if(name==='xjit_todos'&&op==='put'&&!started){started=true;await gate.promise}};
 const add=f.todo.addTodo({title:'Private retired',note:'',dueText:''}),observed=assert.rejects(add,/会话/);await until(()=>started);
 const clear=f.todo.clearTodos();gate.resolve();await Promise.all([observed,clear]);assert.equal(f.state.todoWidgets.length,1);assert.equal(f.state.todoWidgets[0].openCount,0);assert.equal((await f.todo.loadTodos()).length,0);
});
test('logout clears todo storage and desktop data after earlier pending writes',async()=>{
 const f=fixture();await f.seedToken();await f.todo.addTodo({title:'Private',note:'',dueText:''});
 await f.auth.clearSession();assert.equal((await f.todo.loadTodos()).length,0);
 assert.equal(JSON.parse(f.stores.get('xjit_todos').data.get('items')).length,0);
 assert.equal(f.state.todoWidgets.at(-1).openCount,0);
});
test('todo commits publish real card data while widget failure does not undo saved task',async()=>{
 const f=fixture();const rows=await f.todo.addTodo({title:'Study',note:'private',dueText:''});
 assert.equal(f.state.todoWidgets.at(-1).firstTitle,'Study');f.state.todoWidgetFailure=true;
 const done=await f.todo.toggleTodo(rows[0].id);assert.equal(done[0].done,true);assert.equal(f.state.todoWidgets.at(-1).openCount,0);
 await f.todo.deleteTodo(rows[0].id);assert.equal((await f.todo.loadTodos()).length,0);
});
test('todo desktop card is registered with native route and empty synchronization state',()=>{
 const config=JSON.parse(fs.readFileSync(path.join(root,'entry/src/main/resources/base/profile/campus_form_config.json'),'utf8'));
 const card=config.forms.find(x=>x.name==='CampusTodoCard');assert.ok(card);assert.equal(card.isDefault,false);
 const source=fs.readFileSync(path.join(root,'entry/src/main/ets/widget/pages/CampusTodoCard.ets'),'utf8');
 assert.match(source,/campusRoute: 'todo'/);assert.match(source,/打开应用同步待办/);assert.match(source,/LocalStorageProp\('firstTitle'\)/);
});
test('todo card projection sorts timed open tasks without mutating source',()=>{
 const f=fixture(),project=f.load('entry/src/main/ets/utils/TodoWidgetData.ets').buildTodoWidgetData;
 const item=(id,dueAt,done=false)=>({id,title:id,note:'private note',dueText:'',dueAt,done,createdAt:1,updatedAt:1});
 const rows=[item('untimed'),item('late',300),item('done',50,true),item('early',100),item('middle',200)];
 const data=project(rows,150);assert.equal(data.openCount,4);assert.equal(data.overdueCount,1);
 assert.equal(data.firstTitle,'early');assert.equal(data.secondTitle,'middle');assert.equal(data.thirdTitle,'late');assert.equal(rows[0].id,'untimed');assert.equal(JSON.stringify(data).includes('private note'),false);
 assert.equal(project([],150).firstTitle,'暂无待办');
});
test('todo write failures reach caller and persistence queue recovers',async()=>{
 const f=fixture();f.state.hook=async(name,op)=>{if(name==='xjit_todos'&&op==='put')throw new Error('fixture disk failure')};
 await assert.rejects(f.todo.addTodo({title:'First',note:'',dueText:''}),/fixture disk failure/);
 assert.equal((await f.todo.loadTodos()).length,0);
 f.state.hook=null;await f.todo.addTodo({title:'Second',note:'',dueText:''});
 assert.ok(JSON.parse(f.stores.get('xjit_todos').data.get('items')).some(x=>x.title==='Second'));
});
test('todo storage rejects malformed shapes and keeps valid rows',async()=>{
 for(const raw of ['[null,3,"bad"]',JSON.stringify([{id:'x',title:'bad',note:'',dueText:'',done:'false',createdAt:1,updatedAt:1}])]){
  const f=fixture();await f.prefs('xjit_todos').put('items',raw);assert.equal((await f.todo.loadTodos()).length,0);
 }
 const f=fixture();await f.prefs('xjit_todos').put('items',JSON.stringify([null,{id:'x',title:'Task',note:'',dueText:'',done:false,createdAt:1,updatedAt:2}]));assert.equal((await f.todo.loadTodos())[0].title,'Task');
});
test('non-string preference values cannot silently become an empty todo list',async()=>{
 for(const raw of [42,true,['private']]){
  const f=fixture();await f.prefs('xjit_todos').put('items',raw);await assert.rejects(f.todo.loadTodos(),/类型/);
  await assert.rejects(f.todo.addTodo({title:'New',note:'',dueText:''}));assert.equal(f.stores.get('xjit_todos').data.get('items'),raw);
  await f.todo.clearTodos();assert.equal(f.stores.get('xjit_todos').data.get('items'),'[]');
 }
});
test('non-array todo storage roots are preserved until explicit clearing',async()=>{
 for(const raw of ['{}','null','42','"private"']){
  const f=fixture();await f.prefs('xjit_todos').put('items',raw);await assert.rejects(f.todo.loadTodos(),/结构/);
  await assert.rejects(f.todo.addTodo({title:'New',note:'',dueText:''}));assert.equal(f.stores.get('xjit_todos').data.get('items'),raw);
  await f.todo.clearTodos();assert.equal(f.stores.get('xjit_todos').data.get('items'),'[]');
 }
});
test('explicit logout clears malformed todo storage without requiring it to parse',async()=>{
 const f=fixture();f.todo.setTodoContext({abilityInfo:{bundleName:'com.xjit.app.acceptance'}});await f.prefs('xjit_todos').put('items','[{"private":"broken"');
 await f.todo.clearTodos();assert.equal(f.stores.get('xjit_todos').data.get('items'),'[]');assert.equal((await f.todo.loadTodos()).length,0);assert.equal(f.state.todoWidgets.at(-1).openCount,0);
});
test('malformed todo JSON stays untouched and blocks additions until repaired',async()=>{
 const f=fixture();const raw='[{"id":"unfinished"';await f.prefs('xjit_todos').put('items',raw);
 await assert.rejects(f.todo.loadTodos());await assert.rejects(f.todo.addTodo({title:'New',note:'',dueText:''}));assert.equal(f.stores.get('xjit_todos').data.get('items'),raw);
 await f.prefs('xjit_todos').put('items','[]');assert.equal((await f.todo.loadTodos()).length,0);
});
test('todo storage deduplicates valid identities before toggle and delete',async()=>{
 const f=fixture(),item={id:'same',title:'First',note:'',dueText:'',done:false,createdAt:1,updatedAt:2};
 await f.prefs('xjit_todos').put('items',JSON.stringify([item,{...item,title:'Duplicate'}]));
 const rows=await f.todo.loadTodos();assert.equal(rows.length,1);assert.equal(rows[0].title,'First');
 assert.equal((await f.todo.toggleTodo('same'))[0].done,true);assert.equal((await f.todo.deleteTodo('same')).length,0);
});
test('todo structured due timestamp survives add toggle and storage while invalid dates fail',async()=>{
 const f=fixture(),due=Date.now()+3600000;
 const rows=await f.todo.addTodo({title:'Study',note:'',dueText:'Tomorrow',dueAt:due});assert.equal(rows[0].dueAt,due);
 assert.equal((await f.todo.toggleTodo(rows[0].id))[0].dueAt,due);
 assert.equal(JSON.parse(f.stores.get('xjit_todos').data.get('items'))[0].dueAt,due);
 for(const dueAt of [NaN,Infinity,-1,1.5,8640000000000001]) await assert.rejects(f.todo.addTodo({title:'Invalid',note:'',dueText:'',dueAt}));
});
test('electricity binding persists in current session and logout clears it',async()=>{
 const f=fixture();await f.seedToken();await f.auth.saveElectricityRoom(' 9#312 ');
 assert.equal(await f.auth.loadElectricityRoom(),'9#312');
 assert.equal(f.stores.get('xjit_session')?.data.get('electricity_room'),'9#312');
 await f.auth.clearSession();assert.equal(await f.auth.loadElectricityRoom(),'');
});
test('a different account never inherits a dormitory bound by another sign-in',async()=>{
 const f=fixture();await f.auth.saveSchoolSession('alice','token-alice',Date.now()+3600000);
 await f.auth.saveElectricityRoom('9#312');assert.equal(await f.auth.loadElectricityRoom(),'9#312');
 const bob=fixture(f.stores);await bob.auth.saveSchoolSession('bob','token-bob',Date.now()+3600000);
 assert.equal(await bob.auth.loadElectricityRoom(),'');
 const aliceAgain=fixture(f.stores);await aliceAgain.auth.saveSchoolSession('alice','token-alice-2',Date.now()+3600000);
 assert.equal(await aliceAgain.auth.loadElectricityRoom(),'');
});
test('logout retires pending electricity binding reads and writes',async()=>{
 const f=fixture();await f.seedToken();await f.auth.saveElectricityRoom('9#312');
 const gate=deferred();let entered=false;
 f.state.hook=async(name,op,key)=>{if(name==='xjit_session'&&op==='get'&&key==='electricity_room'){entered=true;await gate.promise}};
 const read=f.auth.loadElectricityRoom();await until(()=>entered);
 const write=f.auth.saveElectricityRoom('3#312');const logout=f.auth.clearSession();gate.resolve();
 assert.equal(await read,'');await Promise.all([write,logout]);
 assert.equal(f.stores.get('xjit_session').data.has('electricity_room'),false);
});
test('gateway token alone authorizes all card business without school web authentication', async () => {
  const f = fixture(); await f.auth.saveSchoolSession('student', 'gateway-fixture', Date.now()+3600000, f.cache.getCacheEpoch(), 'xllite-gateway');
  f.state.respond = async () => ({responseCode:200,result:JSON.stringify({ok:true,data:{accounts:[]}})});
  const r = await f.api.callFeature('newcard.balance','student','',{});
  assert.equal(r.ok,true); assert.equal(f.state.requests.length,1); assert.equal(f.state.requests[0].options.header.Authorization,'Bearer gateway-fixture');
});
test('changing from school session to gateway cannot reuse school cache', async () => {
  const f = fixture(); await f.seedToken(); await f.api.callFeature('jw.profile','student','',{});
  await f.auth.saveSchoolSession('student','gateway-fixture',Date.now()+3600000,f.cache.getCacheEpoch(),'xllite-gateway');
  f.state.respond = async () => ({responseCode:200,result:JSON.stringify({ok:true,data:{name:'gateway-name'}})});
  const r = await f.api.callFeature('jw.profile','student','',{}); assert.equal(r.data.name,'gateway-name'); assert.equal(r.fromCache,false);
});
test('gateway schedule merges public confirmed calendar before returning business data',async()=>{
 const f=fixture(); await f.auth.saveSchoolSession('student','gateway-fixture',Date.now()+3600000,f.cache.getCacheEpoch(),'xllite-gateway');
 f.state.respond=async q=>({responseCode:200,result:JSON.stringify({ok:true,data:q.url.includes('academic-calendar')?{schemaVersion:1,timezone:'Asia/Shanghai',term:'2026-2027-1',status:'confirmed',calendar:{term:'2026-2027-1',status:'confirmed',firstMonday:'2026-08-31',weekCount:19,sectionTimes:[],dateOverrides:[]}}:{term:'2026-2027-1',courses:[]}})});
 const r=await f.api.callFeature('jw.schedule','student','',{}); assert.equal(r.ok,true); assert.equal(r.data.termStartDate,'2026-08-31'); assert.equal(r.data.totalWeeks,19);
});
test('near-expiry gateway rotates once before business without replaying payments', async () => {
  const f=fixture(); await f.auth.saveSchoolSession('student','old-token',Date.now()+60000,f.cache.getCacheEpoch(),'xllite-gateway');
  f.state.respond=async q=>({responseCode:200,result:JSON.stringify({ok:true,data:q.url.endsWith('/auth/refresh')?{accessToken:'new-token',expiresInSeconds:3600}:{name:'fresh'}})});
  const r=await f.api.callFeature('jw.profile','student','',{}); assert.equal(r.ok,true); assert.equal(f.state.requests.length,2); assert.equal(f.state.requests[0].url.endsWith('/auth/refresh'),true); assert.equal(f.state.requests[1].options.header.Authorization,'Bearer new-token');
});
const CACHE = 'xjit_http_cache', AUTH = 'xjit_session', TODOS = 'xjit_todos';

test('parallel cache writes reuse preferences and batch disk flush', async () => {
  const f = fixture(); await Promise.all([f.cache.setCachedValue('a', { value: 1 }, 10000), f.cache.setCachedValue('b', { value: 2 }, 10000)]);
  assert.equal(f.opens.get(CACHE), 1); assert.equal(f.stores.get(CACHE).flushes, 0); assert.equal(f.timers.size, 1);
  assert.equal((await f.cache.getCachedValue('a')).value, 1); await f.runTimers(); assert.equal(f.stores.get(CACHE).flushes, 1);
});

test('expired persisted cache is served stale and corrupt entries are purged', async () => {
  const f = fixture(); f.prefs(CACHE); const data = f.stores.get(CACHE).data;
  data.set('expired', JSON.stringify({ value: { lastGood: 1 }, expiresAt: Date.now() - 1 })); data.set('broken', '{broken');
  // Stale-while-revalidate: an expired entry that still holds a last-good value is
  // served so the UI keeps it on screen while ApiService refreshes in the background.
  const expiredValue = await f.cache.getCachedValue('expired');
  assert.equal(expiredValue.lastGood, 1);
  assert.equal(f.cache.isCacheFresh('expired'), false);
  // A corrupt entry is never served and is removed from persistence instead of being re-parsed forever.
  assert.equal(await f.cache.getCachedValue('broken'), null);
  assert.equal(data.has('broken'), false);
});

test('logout invalidates a pending persisted read', async () => {
  const f = fixture(), gate = deferred(); let started = false;
  f.prefs(CACHE); f.stores.get(CACHE).data.set('a', JSON.stringify({ value: { old: true }, expiresAt: Date.now() + 10000 }));
  f.state.hook = async (name, op) => { if (name === CACHE && op === 'get') { started = true; await gate.promise; } };
  const pending = f.cache.getCachedValue('a'); await until(() => started); await f.cache.clearAllCachedValues(); gate.resolve();
  assert.equal(await pending, null); assert.equal(f.stores.get(CACHE).data.size, 0);
});

test('logout clears an in-progress cache write before new session data', async () => {
  const f = fixture(), gate = deferred(); let started = false;
  f.state.hook = async (name, op) => { if (name === CACHE && op === 'put' && !started) { started = true; await gate.promise; } };
  const old = f.cache.setCachedValue('old', { old: true }, 10000); await until(() => started);
  const cleared = f.cache.clearAllCachedValues(); const fresh = f.cache.setCachedValue('new', { fresh: true }, 10000); gate.resolve();
  await Promise.all([old, cleared, fresh]); assert.equal(await f.cache.getCachedValue('old'), null); assert.equal((await f.cache.getCachedValue('new')).fresh, true);
});

test('logout during token persistence cannot resurrect credentials', async () => {
  const f = fixture(), gate = deferred(); let started = false;
  await f.seedToken();
  f.state.hook = async (name, op, key) => { if (name === AUTH && op === 'put' && key === 'access_token' && !started) { started = true; await gate.promise; } };
  const old = f.auth.saveSchoolSession('student', 'old-token', Date.now()+3600000); await until(() => started); const cleared = f.auth.clearSession();
  assert.equal(f.auth.getAccessToken(), ''); assert.equal(f.auth.getUsername(), ''); gate.resolve(); await Promise.all([old, cleared]);
  assert.equal(f.stores.get(AUTH).data.size, 0); assert.equal(f.opens.get(AUTH), 1); assert.equal(await f.auth.loadSession(), false);
  await f.auth.saveSchoolSession('new-student', 'new-token', Date.now()+3600000);
  assert.equal(f.stores.get(AUTH).data.get('access_token'), 'new-token'); assert.equal(f.auth.getUsername(), 'new-student');
});

test('concurrent todo initialization waits for one read and returns independent copies', async () => {
  const f = fixture(), gate = deferred(); let started = false, resolved = false;
  f.prefs(TODOS); f.stores.get(TODOS).data.set('items', JSON.stringify([{ id: '1', title: 'task', note: '', dueText: '', done: false, createdAt: 1, updatedAt: 1 }]));
  f.state.hook = async (name, op) => { if (name === TODOS && op === 'get') { started = true; await gate.promise; } };
  const first = f.todo.loadTodos(); await until(() => started); const second = f.todo.loadTodos().then(v => { resolved = true; return v; });
  await Promise.resolve(); assert.equal(resolved, false); gate.resolve(); const [a, b] = await Promise.all([first, second]);
  // One round still reads a fixed key set: cleanup marker, owner tag, rows.
  assert.equal(a.length, 1); assert.equal(b.length, 1); assert.equal(f.stores.get(TODOS).reads, 3); a[0].title = 'changed'; assert.equal(b[0].title, 'task');
});

test('concurrent feature reads deduplicate; cache hit and manual refresh differ', async () => {
  const f = fixture(); await f.seedToken();
  const [a, b] = await Promise.all([f.api.callFeature('newcard.balance', 'student', { b: 2, a: 1 }), f.api.callFeature('newcard.balance', 'student', { a: 1, b: 2 })]);
  assert.equal(a.ok, true); assert.equal(b.ok, true); assert.equal(f.state.requests.length, 1);
  const cached = await f.api.callFeature('newcard.balance', 'student', { a: 1, b: 2 }); assert.equal(cached.fromCache, true); assert.equal(f.state.requests.length, 1);
  const fresh = await f.api.callFeature('newcard.balance', 'student', { _forceRefresh: true, b: 2, a: 1 });
  assert.equal(fresh.fromCache, false); assert.equal(f.state.requests.length, 2); assert.equal('_forceRefresh' in f.state.requests[1].body, false); assert.equal(f.state.created, f.state.destroyed);
});

test('failed school profile and session verification release HTTP sessions and can retry', async () => {
  const f = fixture(); await f.seedToken(); f.state.respond = async () => { throw new Error('mock failure'); };
  assert.equal((await f.api.callFeature('jw.profile', 'student', {})).ok, false); assert.equal(f.state.created, f.state.destroyed);
  assert.equal((await f.load('entry/src/main/ets/services/SchoolNativeApi.ets').acceptSchoolLogin(schoolJwt(),f.cache.getCacheEpoch())).ok, false); assert.equal(f.state.created, f.state.destroyed);
  f.state.respond = null; assert.equal((await f.api.callFeature('jw.profile', 'student', {})).ok, true);
});

test('prewarm shares ongoing reads, skips valid cache and uses at most two requests', async () => {
  const f = fixture(); await f.seedToken(); await f.api.callFeature('newcard.balance', 'student', {}); f.state.requests.length = 0; f.state.peak = 0;
  await Promise.all([f.api.prewarmCampusData('student'), f.api.prewarmCampusData('student'), f.api.callFeature('jw.profile', 'student', {})]);
  assert.deepEqual(f.state.requests.map(r => new URL(r.url).pathname).sort(), ['/personal/api/v1/personal/me/user', '/server/bllt/queryCardSelfTradeList']); assert.ok(f.state.peak <= 2);
  const count = f.state.requests.length; await f.api.prewarmCampusData('student'); assert.equal(f.state.requests.length, count);
});

test('background or hidden main page skips the second prewarm stage', async () => {
  for (const key of ['appActive', 'mainPageActive']) {
    const f = fixture(), gate = deferred(); await f.seedToken();
    f.state.respond = async request => { await gate.promise; return schoolResponse(request); };
    const pending = f.api.prewarmCampusData('student'); await until(() => f.state.active === 2); f.state[key] = false; gate.resolve(); await pending;
    assert.deepEqual(f.state.requests.map(r => new URL(r.url).pathname).sort(), ['/personal/api/v1/personal/me/user', '/server/user/info']);
  }
});

test('logout rejects a late network response without repopulating cache', async () => {
  const f = fixture(), gate = deferred(); await f.seedToken();
  f.state.respond = async request => { await gate.promise; return schoolResponse(request); };
  const pending = f.api.callFeature('newcard.balance', 'student', {}); await until(() => f.state.active === 1);
  await f.auth.clearSession(); gate.resolve(); assert.equal((await pending).ok, false); assert.equal(f.stores.get(CACHE).data.size, 0); assert.equal(f.state.created, f.state.destroyed);
});

test('logout during a 401 token clear prevents reauthentication by the old request', async () => {
  const f = fixture(), gate = deferred(); let started = false; await f.seedToken();
  f.state.respond = async () => ({ responseCode: 401, result: JSON.stringify({ error: 'expired' }) });
  f.state.hook = async (name, op, key) => { if (name === AUTH && op === 'delete' && key === 'access_token' && !started) { started = true; await gate.promise; } };
  const pending = f.api.callFeature('jw.profile', 'student', {}); await until(() => started); const cleared = f.auth.clearSession(); gate.resolve();
  const result = await pending; await cleared; assert.equal(result.ok, false); assert.equal(f.state.requests.filter(r => r.url.endsWith('/auth/login')).length, 0); assert.equal(f.auth.getAccessToken(), '');
});


test('prewarm does not start when already backgrounded or hidden', async () => {
  for (const key of ['appActive', 'mainPageActive']) {
    const f = fixture(); await f.seedToken(); f.state[key] = false;
    await f.api.prewarmCampusData('student'); assert.equal(f.state.requests.length, 0);
  }
});

test('system theme changes respect the explicit light/dark preference', async () => {
  const f = fixture(); await f.theme.initTheme({}); f.theme.updateSystemTheme(true); assert.equal(f.state.isDark, true);
  await f.theme.setThemeMode('light'); f.theme.updateSystemTheme(true); assert.equal(f.state.isDark, false);
  await f.theme.setThemeMode('dark'); f.theme.updateSystemTheme(false); assert.equal(f.state.isDark, true);
  await f.theme.setThemeMode('system'); assert.equal(f.state.isDark, false);
});

test('native dialogs follow theme only after the window is ready and release the override in system mode',async()=>{
 const f=fixture(),modes=[];await f.theme.initTheme({setColorMode:mode=>modes.push(mode)});await f.theme.setThemeMode('dark');assert.deepEqual(modes,[]);
 f.theme.setNativeThemeReady(true);assert.deepEqual(modes,[0]);f.theme.updateSystemTheme(false);assert.deepEqual(modes,[0]);
 await f.theme.setThemeMode('light');await f.theme.setThemeMode('system');assert.deepEqual(modes,[0,1,-1]);
 f.theme.setNativeThemeReady(false);await f.theme.setThemeMode('dark');assert.deepEqual(modes,[0,1,-1]);f.theme.setNativeThemeReady(true);assert.deepEqual(modes,[0,1,-1,0]);
});
test('late theme restore cannot overwrite a user selection', async () => {
  const f = fixture(), gate = deferred(); let started = false; f.prefs('xjit_theme'); f.stores.get('xjit_theme').data.set('mode', 'light');
  f.state.hook = async (name, op) => { if (name === 'xjit_theme' && op === 'get') { started = true; await gate.promise; } };
  const restore = f.theme.initTheme({}); await until(() => started); await f.theme.setThemeMode('dark'); gate.resolve(); await restore;
  assert.equal(f.state.themeMode, 'dark'); assert.equal(f.state.isDark, true);
});

test('rapid theme choices persist in order with one preferences instance', async () => {
  const f = fixture(), gate = deferred(); let started = false; await f.theme.initTheme({});
  f.state.hook = async (name, op) => { if (name === 'xjit_theme' && op === 'put' && !started) { started = true; await gate.promise; } };
  const first = f.theme.setThemeMode('light'); await until(() => started); const second = f.theme.setThemeMode('dark');
  assert.equal(f.state.isDark, true); gate.resolve(); await Promise.all([first, second]);
  assert.equal(f.stores.get('xjit_theme').data.get('mode'), 'dark'); assert.equal(f.opens.get('xjit_theme'), 1);
});

test('reduced motion restores independently of theme selection', async () => {
  const f = fixture(); f.prefs('xjit_theme'); const data = f.stores.get('xjit_theme').data;
  data.set('reduceMotion', true); data.set('mode', 'dark');
  await f.theme.initTheme({}); assert.equal(f.state.reduceMotion, true); assert.equal(f.state.isDark, true);
  await f.theme.setReduceMotion(false); assert.equal(f.state.reduceMotion, false);
  assert.equal(data.get('reduceMotion'), false); assert.equal(data.get('mode'), 'dark');
});

test('late motion restoration cannot overwrite a user toggle', async () => {
  const f = fixture(), gate = deferred(); let started = false;
  f.prefs('xjit_theme'); f.stores.get('xjit_theme').data.set('reduceMotion', false);
  f.state.hook = async (name, op, key) => { if (name === 'xjit_theme' && op === 'get' && key === 'reduceMotion') { started = true; await gate.promise; } };
  const restore = f.theme.initTheme({}); await until(() => started);
  await f.theme.setReduceMotion(true); gate.resolve(); await restore;
  assert.equal(f.state.reduceMotion, true); assert.equal(f.stores.get('xjit_theme').data.get('reduceMotion'), true);
});

test('rapid motion and theme toggles persist the final choices in order', async () => {
  const f = fixture(), gate = deferred(); let started = false; await f.theme.initTheme({});
  f.state.hook = async (name, op) => { if (name === 'xjit_theme' && op === 'put' && !started) { started = true; await gate.promise; } };
  const first = f.theme.setReduceMotion(true); await until(() => started);
  const second = f.theme.setThemeMode('dark'), third = f.theme.setReduceMotion(false);
  assert.equal(f.state.reduceMotion, false); assert.equal(f.state.isDark, true);
  gate.resolve(); await Promise.all([first, second, third]);
  const data = f.stores.get('xjit_theme').data; assert.equal(data.get('reduceMotion'), false);
  assert.equal(data.get('mode'), 'dark'); assert.equal(f.opens.get('xjit_theme'), 1);
});

test('lazy list snapshot updates notify each mounted listener once', () => {
  const f = fixture(); const { ListDataSource } = f.load('entry/src/main/ets/utils/ListDataSource.ets');
  const rows = new ListDataSource(); let first = 0, second = 0;
  const a = { onDataReloaded() { first++; } }, b = { onDataReloaded() { second++; } };
  rows.registerDataChangeListener(a); rows.registerDataChangeListener(a); rows.registerDataChangeListener(b);
  const input = [{ id: 'one' }, { id: 'two' }]; rows.replace(input); input.push({ id: 'outside' });
  assert.equal(rows.totalCount(), 2); assert.equal(rows.getData(1).id, 'two'); assert.equal(first, 1); assert.equal(second, 1);
  rows.unregisterDataChangeListener(a); rows.unregisterDataChangeListener(a); rows.replace([]);
  assert.equal(rows.totalCount(), 0); assert.equal(first, 1); assert.equal(second, 2);
});


// School-native transport/schema checks. Actual ETS modules, mocked HTTP/OS only.
test('school profile uses the verified HTTPS service and X-Id-Token',async()=>{
 const f=fixture();await f.seedToken();const r=await f.api.callFeature('jw.profile','student',{});assert.equal(r.ok,true);assert.equal(r.data.studentId,'student');
 const q=f.state.requests[0];assert.equal(q.url,'https://authx-service.xjit.edu.cn/personal/api/v1/personal/me/user');assert.equal(q.options.method,'GET');assert.equal(q.options.header['X-Id-Token'],f.auth.getAccessToken());assert.equal(q.options.header.Authorization,undefined);assert.equal(q.options.usingCache,false);assert.deepEqual(q.body,{});
});
test('school card uses its own authorization and native amount mapping',async()=>{
 const f=fixture();await f.seedToken();const r=await f.api.callFeature('newcard.balance','student',{});assert.equal(r.ok,true);assert.equal(r.data.accounts[0].balance,'12.34');
 const q=f.state.requests[0];assert.equal(q.url,'https://newcard.xjit.edu.cn/server/user/info');assert.equal(q.options.method,'POST');assert.equal(q.options.header.Authorization,'fixture-card-token');assert.equal(q.options.header['X-Id-Token'],undefined);assert.deepEqual(q.body,{});
});
test('school transactions use verified parameters and convert minor units',async()=>{
 const f=fixture();await f.seedToken();const r=await f.api.callFeature('newcard.transactions','student',{fromDate:'2026-10-01',toDate:'2026-10-09',pageNo:2});assert.equal(r.ok,true);assert.equal(r.data.transactions[0].amount,'6.50');
 assert.equal(f.state.requests[0].url,'https://newcard.xjit.edu.cn/server/bllt/queryCardSelfTradeList');assert.deepEqual(f.state.requests[0].body,{starttime:'2026-10-01',endtime:'2026-10-09',tradetype:'-1',pageNumber:1,pageSize:20});
});
test('invalid native dates and page numbers cause no HTTP request',async()=>{
 for(const params of [{fromDate:'2026-02-30'},{fromDate:'2026-10-10',toDate:'2026-10-09'},{pageNo:-1},{pageNo:1.5},{pageNo:'bad'}]){const f=fixture();await f.seedToken();assert.equal((await f.api.callFeature('newcard.transactions','student',params)).ok,false);assert.equal(f.state.requests.length,0);}
});
test('legacy migration clears old account data and does not forward it',async()=>{
 const f=fixture();f.prefs(AUTH);const old=f.stores.get(AUTH).data;old.set('username','legacy');old.set('access_token','legacy');await f.cache.setCachedValue('legacy',{private:'old'},10000);
 assert.equal(await f.auth.loadSession(),false);assert.equal(old.size,0);assert.equal(await f.cache.getCachedValue('legacy'),null);assert.equal(f.auth.getAccessToken(),'');assert.equal(f.state.requests.length,0);
});
test('JWT expiry rejects invalid sessions before contacting school',async()=>{
 for(const token of ['invalid','a.bad.a',schoolJwt(1)]){const f=fixture();const n=f.load('entry/src/main/ets/services/SchoolNativeApi.ets');assert.equal((await n.acceptSchoolLogin(token,f.cache.getCacheEpoch())).ok,false);assert.equal(f.state.requests.length,0);assert.equal(f.auth.getUsername(),'');}
});
test('school profile verification is required before a session is saved',async()=>{
 const f=fixture(),n=f.load('entry/src/main/ets/services/SchoolNativeApi.ets');f.state.respond=async()=>({responseCode:200,result:JSON.stringify({code:1,data:{}})});assert.equal((await n.acceptSchoolLogin(schoolJwt(),f.cache.getCacheEpoch())).ok,false);assert.equal(f.auth.getAccessToken(),'');
 f.state.respond=null;assert.equal((await n.acceptSchoolLogin(schoolJwt(),f.cache.getCacheEpoch())).ok,true);assert.equal(f.stores.get(AUTH).data.get('protocol'),'school-native-v1');assert.equal(f.auth.getUsername(),'student');
});
test('failed persistence is not reported as successful school login',async()=>{
 const f=fixture();f.state.hook=async(name,op,key)=>{if(name===AUTH&&op==='put'&&key==='access_token')throw Error('disk unavailable');};const n=f.load('entry/src/main/ets/services/SchoolNativeApi.ets');assert.equal((await n.acceptSchoolLogin(schoolJwt(),f.cache.getCacheEpoch())).ok,false);assert.equal(f.auth.getAccessToken(),'');
});
test('logout rejects late school login verification',async()=>{
 const f=fixture(),g=deferred();f.state.respond=async q=>{await g.promise;return schoolResponse(q);};const n=f.load('entry/src/main/ets/services/SchoolNativeApi.ets'),pending=n.acceptSchoolLogin(schoolJwt(),f.cache.getCacheEpoch());await until(()=>f.state.active===1);await f.auth.clearSession();g.resolve();assert.equal((await pending).ok,false);assert.equal(f.auth.getUsername(),'');
});
test('card session needs native verification and a live owner',async()=>{
 const f=fixture();await f.seedToken();f.auth.clearCardToken();const n=f.load('entry/src/main/ets/services/SchoolNativeApi.ets');assert.equal((await n.acceptSchoolCardLogin('new-card',Date.now()+3600000,f.cache.getCacheEpoch(),'different-owner')).ok,false);assert.equal(f.state.requests.length,0);
 assert.equal((await n.acceptSchoolCardLogin('new-card',Date.now()+3600000,f.cache.getCacheEpoch(),'student')).ok,true);assert.equal(f.auth.getCardToken(),'new-card');
});
test('card credential changes prevent reuse of old cache and late results',async()=>{
 const f=fixture();await f.seedToken();await f.api.callFeature('newcard.balance','student',{});f.auth.clearCardToken();assert.equal((await f.api.callFeature('newcard.balance','student',{})).ok,false);f.auth.saveCardToken('new-card',Date.now()+3600000,f.cache.getCacheEpoch());assert.equal((await f.api.callFeature('newcard.balance','student',{})).fromCache,false);assert.equal(f.state.requests.length,2);
 const g=deferred();f.state.respond=async q=>{await g.promise;return schoolResponse(q);};const pending=f.api.callFeature('newcard.balance','student',{_forceRefresh:true});await until(()=>f.state.active===1);f.auth.saveCardToken('another-card',Date.now()+3600000,f.cache.getCacheEpoch());g.resolve();assert.equal((await pending).ok,false);
});
test('wrong portal account cannot read cached personal information',async()=>{
 const f=fixture();await f.seedToken();await f.api.callFeature('jw.profile','student',{});assert.equal((await f.api.callFeature('jw.profile','another',{})).ok,false);assert.equal(f.state.requests.length,1);
});
test('late card 401 cannot invalidate a newer card connection',async()=>{
 const f=fixture(),g=deferred();await f.seedToken();f.state.respond=async()=>{await g.promise;return{responseCode:401,result:'{}'};};const p=f.api.callFeature('newcard.balance','student',{});await until(()=>f.state.active===1);f.auth.saveCardToken('new-card',Date.now()+3600000,f.cache.getCacheEpoch());g.resolve();await p;assert.equal(f.auth.getCardToken(),'new-card');assert.notEqual(f.auth.getAccessToken(),'');
});
test('school SM4 envelope decrypts with actual CryptoUtil and an OS provider mock',async()=>{
 const f=fixture();const text=JSON.stringify({success:true,resultData:{user:{balance:'19.87'}}});const c=crypto.createCipheriv('sm4-ecb',Buffer.from('w687-9+3C_H&je_5'),null);const encoded=Buffer.concat([c.update(text),c.final()]).toString('base64');
 assert.equal(await f.load('entry/src/main/ets/utils/CryptoUtil.ets').decryptSchoolCardEnvelope(encoded),text);await f.seedToken();f.state.respond=async()=>({responseCode:200,result:JSON.stringify({success:false,data:encoded})});assert.equal((await f.api.callFeature('newcard.balance','student',{})).data.accounts[0].balance,'19.87');
});
test('malformed native response and ciphertext always release HTTP sessions',async()=>{
 for(const result of ['{broken',JSON.stringify({ok:true,data:{}}),JSON.stringify({success:false,data:'invalid'}),JSON.stringify({success:true,resultData:[]})]){const f=fixture();await f.seedToken();f.state.respond=async()=>({responseCode:200,result});assert.equal((await f.api.callFeature('newcard.balance','student',{})).ok,false);assert.equal(f.state.created,f.state.destroyed);}
});
test('native schemas reject invalid amounts and missing transaction arrays',()=>{
 const n=fixture().load('entry/src/main/ets/services/SchoolNativeApi.ets');for(const balance of [null,'','bad',{},'NaN'])assert.throws(()=>n.normalizeSchoolBalance({user:{balance}}));assert.throws(()=>n.normalizeSchoolTransactions({rows:null,totalpage:1},{}));assert.throws(()=>n.normalizeSchoolTransactions({rows:[{txamt:null}],totalpage:1},{}));assert.throws(()=>n.normalizeSchoolTransactions({rows:[]},{}));
});
test('unimplemented school features cannot send guessed requests or retry payments',async()=>{
 const f=fixture();await f.seedToken();for(const feature of ['jw.schedule','jw.grades','jw.exams','jw.training','newcard.campus_code.qrcode','newcard.recharge.config','newcard.recharge.create_order','newcard.electricity.account','newcard.electricity.recharge.config','newcard.electricity.recharge.pay']){const r=await f.api.callFeature(feature,'student',{});assert.equal(r.ok,false);assert.equal(r.statusCode,501);}assert.equal(f.state.requests.length,0);
});
test('logout clears private school storage and increments card generation',async()=>{
 const f=fixture();await f.seedToken();const epoch=f.auth.getCardSessionEpoch();await f.auth.clearSession();assert.equal(f.auth.getCardToken(),'');assert.ok(f.auth.getCardSessionEpoch()>epoch);assert.equal(f.state.cookieClears,1);assert.equal(f.state.storageClears,1);
test('toast failure is logged instead of vanishing',()=>{
test('theme and motion persistence failures are reported instead of swallowed', async () => {
 // 界面已经按新值切过去了。若把写入失败吞掉并返回成功，用户会以为设置已保存，
 // 重启却回到旧值——主题与减少动效都是用户显式选择的偏好，静默丢失体验最差。
 const f = fixture(); await f.theme.initTheme({});
 f.state.hook = async (name, op) => { if (name === 'xjit_theme' && op === 'put') throw Error('fixture disk full'); };
 assert.equal(await f.theme.setThemeMode('dark'), false, 'failed theme write must not report success');
 assert.equal(await f.theme.setReduceMotion(true), false, 'failed motion write must not report success');
});

test('a failed setting write does not stall later writes', async () => {
test('a signed-out session never reads rows left by another account', async () => {
 // ownerTag() 在无账号时返回空串，磁盘上 owner 键缺失的默认值也是空串。
 // 只看相等性会把「没有账号」认成「同一个账号」，上一个账号的待办就被读出来了。
 const f = fixture(); f.todo.setTodoOwner('student-a');
 await f.todo.addTodo({ title: 'A private', note: '', dueText: '' });
 f.todo.setTodoOwner('');
 assert.equal((await f.todo.loadTodos()).length, 0, 'signed-out read must not return private rows');
});

test('a stored owner with no current account counts as a different owner', async () => {
test('clearing keeps the disk owner tag instead of blanking it', async () => {
test('a failed cache wipe makes logout fail instead of pretending success', async () => {
test('a signed-out read leaves the other account data untouched on disk', async () => {
 // 未登录时既不能读到别人的待办，也不能把别人的待办抹掉。曾经的归属分支在
 // owner 为空串时会清空行、把 owner 写成空串——用户只是没登录，数据就没了。
 const f = fixture(); f.todo.setTodoOwner('student-a');
 await f.todo.addTodo({ title: 'A private', note: '', dueText: '' });
 const disk = f.stores.get('xjit_todos').data;
 const ownerBefore = disk.get('owner'); const itemsBefore = disk.get('items');
 f.todo.setTodoOwner('');
 assert.equal((await f.todo.loadTodos()).length, 0, 'signed-out read must stay empty');
 assert.equal(disk.get('owner'), ownerBefore, 'the owner tag must not be rewritten');
 assert.equal(disk.get('items'), itemsBefore, 'the rows must survive a signed-out read');
});
 // 磁盘上留的是课表、成绩、流水这类隐私数据。清盘失败若被吞掉，clearSession
 // 的 Promise.all 会当作成功，用户看到「已退出登录」而数据还在盘上。
 const f = fixture(); await f.seedToken();
 f.state.hook = async (name, op) => { if (name === 'xjit_http_cache' && op === 'clear') throw Error('fixture cache wipe failed'); };
 await assert.rejects(f.auth.clearSession(), /cache wipe failed/);
});
 // clearSession 先 setTodoOwner('') 再 clearTodos()。若清理时用当前（空）标记
 // 覆盖磁盘 owner，同一账号下次登录也会被当成异账号而白做一次重置。
 const f = fixture(); f.todo.setTodoOwner('student-a');
 await f.todo.addTodo({ title: 'A task', note: '', dueText: '' });
 const before = f.stores.get('xjit_todos').data.get('owner');
 f.todo.setTodoOwner('');
 await f.todo.clearTodos();
 assert.equal(f.stores.get('xjit_todos').data.get('items'), '[]', 'rows must be cleared');
 assert.equal(f.stores.get('xjit_todos').data.get('owner'), before, 'the owner tag must survive the clear');
});
 // 反向确认：清掉 owner 键（模拟旧版本遗留的数据）后，未登录同样读不到。
 const f = fixture(); const disk = f.prefs('xjit_todos');
 disk.put('items', JSON.stringify([{ id: 'old', title: 'Legacy', note: '', dueText: '', done: false, createdAt: 1, updatedAt: 1 }]));
 disk.put('owner', ''); f.todo.setTodoOwner('');
 assert.equal((await f.todo.loadTodos()).length, 0, 'rows without an owner tag must be discarded');
});
 // 失败必须只影响它自己：队列要继续推进，否则一次写入失败会让之后所有设置都存不下去。
 const f = fixture(); await f.theme.initTheme({});
 f.state.hook = async (name, op, key) => { if (name === 'xjit_theme' && op === 'put' && key === 'mode') throw Error('fixture write failed'); };
 assert.equal(await f.theme.setThemeMode('dark'), false);
 f.state.hook = undefined;
 assert.equal(await f.theme.setReduceMotion(true), true, 'the queue must keep running after a failure');
 assert.equal(f.stores.get('xjit_theme').data.get('reduceMotion'), true);
});
 // 这些提示在多数场景是用户唯一的结果反馈。静默吞掉异常等于出问题后无从查起，
 // 但也不能抛出去——调用点都在写入完成之后，抛出会把成功回滚成失败。
 const f=fixture();const {safeToast}=f.load('entry/src/main/ets/utils/ToastHelper.ets');
 const ok={getPromptAction:()=>({showToast(){}})};
 assert.equal(safeToast(ok,'已保存'),true);
 const failing={getPromptAction:()=>({showToast(){throw {code:1001,message:'window not ready'};}})};
 assert.equal(safeToast(failing,'已保存'),false);
 assert.equal(safeToast(ok,''),false,'empty message must not reach the system');
});
});

module.exports = {fixture,deferred,until,schoolJwt,schoolResponse};
if (require.main === module) (async () => {
  let failed = 0;
  for (const t of tests) { try { await t.run(); console.log('PASS ' + t.name); } catch (error) { failed++; console.error('FAIL ' + t.name); console.error(error.stack); } }
  console.log(tests.length + ' checks, ' + failed + ' failed'); process.exitCode = failed ? 1 : 0;
})();
