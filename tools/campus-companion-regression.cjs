"use strict";
// Repeatable checks of actual ArkTS calendar/services with mocked system APIs.
// No account authentication, network, dependency downloads or device writes.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const ts = require('D:/data/devecostudionext/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
const cases = [];
function test(name, run) { cases.push({name, run}); }
function deferred() { let resolve; const promise = new Promise(r => resolve = r); return {promise, resolve}; }
async function until(check) { for (let i=0; i<1000; i++) { if (check()) return; await Promise.resolve(); } throw new Error('Async checkpoint not reached'); }
function fixture() {
  const modules = new Map(), values = new Map(), disks = new Map(), stores = new Map(), openFiles = new Map();
  let nextFile = 1, nextReminder = 1, timer = 1;
  const state = { bundleName: 'com.xjit.app', now: new Date(2026, 9, 12, 7, 45).getTime(), reminders: new Map(), requests: [],
    cancelAll: 0, forms: [], widgetUpdates: [], liveStarts: [], liveUpdates: [], liveStops: [],
    notificationAllowed: true, liveAllowed: true, liveCode: 0, liveError: null, publishHook: null, stopFail: false,
    // Default to the HarmonyOS 6.0 API level so the dynamic-island branches are exercised.
    sdkApiVersion: 20, logs: [] };
  class Clock extends Date { constructor(...args) { if (!args.length) super(state.now); else super(...args); } static now() { return state.now; } }
  const preferences = { async getPreferences(_ctx, name) {
    if (!stores.has(name)) stores.set(name, new Map()); const store = stores.get(name);
    return { async get(k, fallback) { return store.has(k) ? store.get(k) : fallback; }, async put(k,v) {store.set(k,v);},
      async flush() {if(state.preferenceFlushFail)throw Error('fixture preference flush failed');}, async delete(k) {store.delete(k);}, async clear() {store.clear();} };
  }};
  const nativeFs = { OpenMode: {CREATE:1, WRITE_ONLY:2, TRUNC:4},
    readTextSync(p) { if (!disks.has(p)) throw Error('not found'); return disks.get(p); },
    openSync(p) { const fd = nextFile++; openFiles.set(fd,p); return {fd}; },
    writeSync(fd,s) {if(state.writeFail)throw Error('write failed');disks.set(openFiles.get(fd),s);}, closeSync() {state.closedFiles=(state.closedFiles||0)+1;},
    renameSync(a,b) {if(state.renameFail)throw Error('rename failed');disks.set(b,disks.get(a)); disks.delete(a);} };
  const notification = {SlotType:{SERVICE_INFORMATION:2}, async requestEnableNotification(){state.notificationRequests=(state.notificationRequests||0)+1;if(state.notificationRequestHook)await state.notificationRequestHook();}, async isNotificationEnabled(){if(state.notificationQueryHook)await state.notificationQueryHook();return state.notificationAllowed;}};
  const reminder = {ReminderType:{REMINDER_TYPE_CALENDAR:1}, async cancelAllReminders(){state.cancelAll++; state.reminders.clear();},
    async getAllValidReminders(){if(state.allValidHook)await state.allValidHook();if(state.allValidQueryFails)throw Error('query failed');return [...state.reminders].map(([reminderId,reminderReq])=>({reminderId,reminderReq}));},
    async getValidReminders(){if(state.validQueryFails)throw Error('query failed');return [...state.reminders.values()];},
     async cancelReminder(id){if(state.cancelReminderFail||state.cancelReminderFailId===id)throw Error('fixture reminder cancel failed');state.reminders.delete(id);}, async publishReminder(request){
      state.requests.push(request); if (state.publishHook) await state.publishHook(request);
      const id = nextReminder++; state.reminders.set(id,request); return id;
    }};
  const liveViewManager = {LifeCycleMode:{AUTO_STOP_WHEN_APP_TERMINATE:1}, CapsuleType:{CAPSULE_TYPE_TIMER:2},
    async isLiveViewEnabled(){if(state.liveQueryHook)await state.liveQueryHook();return state.liveAllowed;}, async startLiveView(view){
      state.liveStarts.push(JSON.parse(JSON.stringify(view))); if(state.liveError) throw state.liveError;
      return {resultCode:state.liveCode,message:'mock'};
    }, async updateLiveView(view){state.liveUpdates.push(JSON.parse(JSON.stringify(view)));if(state.updateError)throw state.updateError;return {resultCode:state.updateCode||0,message:'mock'};},
    async stopLiveView(view){state.liveStops.push(JSON.parse(JSON.stringify(view))); if(state.stopHook)await state.stopHook(); if(state.stopFail) throw {code:state.stopFailCode||1003500003}; return {resultCode:0,message:'mock'};}};
  const formKit = {formBindingData:{createFormBindingData:data=>({data})}, formProvider:{async getPublishedRunningFormInfos(){return state.forms;},
    async updateForm(id,data){state.widgetUpdates.push({id,...data});}}};
  const wantAgent = {OperationType:{START_ABILITY:0}, WantAgentFlags:{UPDATE_PRESENT_FLAG:0}, async getWantAgent(options){return {options};}};
  function load(rel) {
    const full = path.resolve(root,rel); if(modules.has(full)) return modules.get(full).exports;
    const module={exports:{}}; modules.set(full,module);
    const js=ts.transpileModule(fs.readFileSync(full,'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText;
    // hilog 必须给全 debug/info/warn/error：Logger 封装会按级别分派，
    // 兜底的空对象会让服务层一打日志就抛 TypeError。
    const hilog = { debug(){state.logs.push(['debug',...arguments]);},
      info(){state.logs.push(['info',...arguments]);},
      warn(){state.logs.push(['warn',...arguments]);},
      error(){state.logs.push(['error',...arguments]);} };
    const requireLocal = spec => {
      const native = {'@ohos.data.preferences':preferences,'@ohos.file.fs':nativeFs,'@ohos.notificationManager':notification,
        '@ohos.reminderAgentManager':reminder,'@ohos.app.ability.wantAgent':wantAgent,'@ohos.hilog':hilog};
      if(native[spec]) return {default:native[spec]};
      if(spec==='@ohos.deviceInfo') return {default:{sdkApiVersion:state.sdkApiVersion}};
      if(spec==='@kit.LiveViewKit') return {liveViewManager}; if(spec==='@kit.FormKit') return formKit;
      if(spec.startsWith('@ohos.')) return {default:{}};
      return load(path.relative(root,path.resolve(path.dirname(full),spec+'.ets')));
    };
    const context = vm.createContext({exports:module.exports,module,require:requireLocal,console,Date:Clock,Map,Set,Promise,
      AppStorage:{get:k=>values.get(k),set:(k,v)=>values.set(k,v),setOrCreate:(k,v)=>values.set(k,v)},
      setInterval:()=>timer++,clearInterval(){},setTimeout:()=>timer++,clearTimeout(){}});
    vm.runInContext(js,context,{filename:full}); return module.exports;
  }
  const get = file => load('entry/src/main/ets/'+file+'.ets');
  return {state,values,disks,stores,get,clock:Clock,calendar:get('utils/CourseCalendar'), layout:get('utils/ScheduleLayout'),time:get('utils/ClassTime'),weeks:get('utils/WeekParser'),
    async boot(){const core=get('services/CampusCompanionService');await core.initCampusCompanion({filesDir:'/data',abilityInfo:{bundleName:state.bundleName}});return core;}};
}
test('form binding selects todo placeholder separately from schedule',()=>{
 const f=fixture(),service=f.get('services/WidgetService');
 const todo=service.buildFormBinding({filesDir:'/data'},'CampusTodoCard').data;
 assert.equal(todo.firstTitle,'打开应用同步待办');assert.equal(todo.courseTitle,undefined);
 const schedule=service.buildFormBinding({filesDir:'/data'},'CampusScheduleCard').data;assert.ok(schedule.courseTitle);assert.equal(schedule.firstTitle,undefined);
});
test('todo form snapshot roundtrips and corrupt counts fall back',()=>{
 const f=fixture(),service=f.get('services/WidgetService'),ctx={filesDir:'/data'};
 service.saveTodoWidgetSnapshot(ctx,{openCount:2,overdueCount:1,firstTitle:'Study',secondTitle:'Read',thirdTitle:''});
 assert.equal(service.buildFormBinding(ctx,'CampusTodoCard').data.firstTitle,'Study');
 f.disks.set('/data/todo_widget.json',JSON.stringify({openCount:-1,overdueCount:0,firstTitle:'Bad',secondTitle:'',thirdTitle:''}));
 assert.equal(service.buildFormBinding(ctx,'CampusTodoCard').data.firstTitle,'打开应用同步待办');
});
test('todo publication persists snapshot and refreshes only todo forms',async()=>{
 const f=fixture(),service=f.get('services/WidgetService'),ctx={filesDir:'/data'};
 f.state.forms=[{formName:'CampusScheduleCard',formId:'schedule'},{formName:'CampusTodoCard',formId:'todo'}];
 await service.publishTodoWidgets(ctx,{openCount:1,overdueCount:0,firstTitle:'Study',secondTitle:'',thirdTitle:''});
 assert.equal(f.state.widgetUpdates.length,1);assert.equal(f.state.widgetUpdates[0].id,'todo');assert.equal(f.state.widgetUpdates[0].data.firstTitle,'Study');
 assert.equal(service.buildFormBinding(ctx,'CampusTodoCard').data.firstTitle,'Study');
});
test('group reminder cancellation preserves unrelated reminders and surfaces query failure',async()=>{
 const f=fixture(),service=f.get('services/ReminderGroups');
 f.state.reminders.set(1,{groupId:'campus_courses'});f.state.reminders.set(2,{groupId:'campus_todos'});
 await service.cancelReminderGroup('campus_courses');assert.equal(f.state.reminders.has(1),false);assert.equal(f.state.reminders.has(2),true);assert.equal(f.state.cancelAll,0);
 f.state.allValidQueryFails=true;await assert.rejects(service.cancelReminderGroup('campus_todos'),/query failed/);assert.equal(f.state.reminders.has(2),true);
});
test('group cancellation attempts later reminders after one native cancellation fails',async()=>{
 const f=fixture(),service=f.get('services/ReminderGroups');f.state.reminders.set(1,{groupId:'campus_courses'});f.state.reminders.set(2,{groupId:'campus_courses'});f.state.reminders.set(3,{groupId:'campus_todos'});f.state.cancelReminderFailId=1;
 await assert.rejects(service.cancelReminderGroup('campus_courses'),/reminder cancel failed/);assert.equal(f.state.reminders.has(1),true);assert.equal(f.state.reminders.has(2),false);assert.equal(f.state.reminders.has(3),true);assert.equal(f.state.cancelAll,0);
});
test('course reminder reconciliation preserves todo reminders',async()=>{
 const f=fixture(),core=await readyCourse(f);f.state.reminders.set(9999,{groupId:'campus_todos'});
 await core.setCampusOption('reminders',true);assert.equal(f.state.reminders.has(9999),true);
 await core.setCampusOption('reminders',false);assert.equal(f.state.reminders.has(9999),true);assert.equal(f.state.cancelAll,0);
});
test('todo native reminder count reads only todo group without publishing',async()=>{
 const f=fixture(),service=f.get('services/TodoReminderService');f.state.reminders.set(1,{groupId:'campus_courses'});f.state.reminders.set(2,{groupId:'campus_todos'});
 assert.equal(await service.getTodoReminderCount(),1);assert.equal(f.state.requests.length,0);assert.equal(f.state.reminders.size,2);
 f.state.allValidQueryFails=true;await assert.rejects(service.getTodoReminderCount(),/query failed/);
});
test('todo reminder service registers native todo routes and preserves courses',async()=>{
 const f=fixture(),service=f.get('services/TodoReminderService');f.state.reminders.set(9999,{groupId:'campus_courses'});
 const due=f.clock.now()+3600000,item={id:'task',title:'Study',note:'',dueText:'',dueAt:due,done:false,createdAt:1,updatedAt:1};
 assert.equal(await service.syncTodoReminders([item],'com.xjit.app.acceptance'),1);
 assert.equal(f.state.requests.at(-1).groupId,'campus_todos');assert.equal(f.state.requests.at(-1).wantAgent.parameters.campusRoute,'todo');assert.equal(f.state.reminders.has(9999),true);
 f.state.publishHook=async()=>{throw new Error('fixture publication failed')};await assert.rejects(service.syncTodoReminders([item],'com.xjit.app.acceptance'),/publication failed/);assert.equal(f.state.reminders.size,1);
});
 test('a reminder published during logout is withdrawn again',async()=>{
  // publishReminder 是异步的：版本检查通过到真正登记完成之间用户可能已登出，
  // 而登出时的 cancelReminderGroup 早已跑完。不补一次撤销，这条提醒会留在系统里，
  // 下一个账号登录后照常弹出。
  const f=fixture(),service=f.get('services/TodoReminderService'),due=f.clock.now()+3600000;
  const item={id:'task',title:'Study',note:'',dueText:'',dueAt:due,done:false,createdAt:1,updatedAt:1};
  let logoutStarted=false;
  // 只触发登出，不 await：clearTodoReminders 的取消任务排在同一个队列后面，
  // 在 publishHook 里等它完成会互相等待。版本号是同步递增的，足以让本次登记作废。
  f.state.publishHook=async()=>{ if(!logoutStarted){ logoutStarted=true; service.clearTodoReminders().catch(()=>{}); } };
  const count=await service.syncTodoReminders([item],'com.xjit.app.acceptance');
  assert.equal(count,0,'a publication interrupted by logout must not report success');
  assert.equal(f.state.reminders.size,0,'no reminder may survive the logout');
 });
test('todo publication plus rollback failure retains both diagnostic causes',async()=>{
 const f=fixture(),service=f.get('services/TodoReminderService'),due=f.clock.now()+3600000;
 const item=id=>({id,title:id,note:'',dueText:'',dueAt:due,done:false,createdAt:1,updatedAt:1});let calls=0;
 f.state.publishHook=async()=>{if(++calls===2){f.state.cancelReminderFail=true;throw Error('fixture publication failed')}};
 await assert.rejects(service.syncTodoReminders([item('a'),item('b')],'com.xjit.app.acceptance'),error=>error.message.includes('publication failed')&&error.message.includes('清理未完成'));
 f.state.cancelReminderFail=false;await service.clearTodoReminders();assert.equal(f.state.reminders.size,0);
});
test('todo reminders skip elapsed triggers after native query and earlier publication',async()=>{
 for(const stage of ['query','publish']){
  const f=fixture(),service=f.get('services/TodoReminderService'),due=f.clock.now()+3600000;
  const item=(id,time)=>({id,title:id,note:'',dueText:'',dueAt:time,done:false,createdAt:1,updatedAt:1});
  const advance=async()=>{f.state.now=due+180000};if(stage==='query')f.state.allValidHook=advance;else f.state.publishHook=advance;
  const count=await service.syncTodoReminders([item('first',due),item('second',due+60000)],'com.xjit.app.acceptance');
  assert.equal(count,stage==='query'?0:1);assert.equal(f.state.requests.length,count);
 }
});
test('todo reminder synchronization serializes overlapping replacement plans',async()=>{
 const f=fixture(),service=f.get('services/TodoReminderService');let release,entered=false;
 const gate=new Promise(r=>release=r);f.state.publishHook=async()=>{if(!entered){entered=true;await gate}};
 const item=title=>({id:title,title,note:'',dueText:'',dueAt:f.clock.now()+3600000,done:false,createdAt:1,updatedAt:1});
 const first=service.syncTodoReminders([item('First')],'com.xjit.app.acceptance');
 for(let i=0;i<100&&!entered;i++)await Promise.resolve();assert.equal(entered,true);
 const second=service.syncTodoReminders([item('Second')],'com.xjit.app.acceptance');
 for(let i=0;i<20;i++)await Promise.resolve();release();await Promise.all([first,second]);
 assert.equal(f.state.reminders.size,1);assert.ok([...f.state.reminders.values()][0].title.includes('Second'));
});
test('todo reminder clear retires queued plans after active publication',async()=>{
 const f=fixture(),service=f.get('services/TodoReminderService');let release,entered=false;const gate=new Promise(r=>release=r);
 f.state.reminders.set(9999,{groupId:'campus_courses'});f.state.publishHook=async()=>{entered=true;await gate};
 const item={id:'old',title:'Old',note:'',dueText:'',dueAt:f.clock.now()+3600000,done:false,createdAt:1,updatedAt:1};
 const first=service.syncTodoReminders([item,{...item,id:'second',title:'Second'}],'com.xjit.app.acceptance');for(let i=0;i<100&&!entered;i++)await Promise.resolve();assert.equal(entered,true);
 const queued=service.syncTodoReminders([item],'com.xjit.app.acceptance');const clear=service.clearTodoReminders();release();
 await Promise.all([first,queued,clear]);assert.equal(f.state.requests.length,1);assert.equal(f.state.reminders.size,1);assert.equal(f.state.reminders.has(9999),true);
});
function course(extra={}) { return {day:'星期一',slot:'1-2节',title:'高等数学',teacher:'教师',weeks:'1-20周',sections:'1-2节',location:'教学楼A101',...extra}; }
function snapshot(extra={}) { return {account:'test-student',term:'2026-2027-1',courses:[course()],currentWeek:6,totalWeeks:20,weekKnown:true,
  anchorDate:'2026-10-12',updatedAt:new Date(2026,9,12).getTime(),widgetEnabled:true,...extra}; }
const plain=v=>JSON.parse(JSON.stringify(v));
async function readyCourse(f, courses=[course()], data={}) {
  const core=await f.boot(); await core.activateCampusCompanion('test-student');
  await core.acceptCampusSchedule('test-student',{term:'2026-2027-1',currentWeek:6,totalWeeks:20,courses,scheduleFetchedAt:f.state.now,...data},0); return core;
}

test('verified XJIT section clock matches confirmed 2026 autumn calendar',()=>{
 const f=fixture();
 assert.deepEqual(plain(f.time.parseSections('1-2节')),[600,700]);
 assert.deepEqual(plain(f.time.parseSections('3-4节')),[720,820]);
 assert.deepEqual(plain(f.time.parseSections('5-6节')),[960,1060]);
 assert.deepEqual(plain(f.time.parseSections('7-8节')),[1080,1180]);
 assert.deepEqual(plain(f.time.parseSections('9-10节')),[1230,1330]);
 assert.equal(f.time.ALL_TIMES.length,10);
 // 上午/下午/晚自习三段同构：45 分一节、小课间 10 分、大课间 20 分，末段 13:40 / 19:40 / 22:10 下课
 assert.deepEqual(plain(f.time.ALL_TIMES.map(t=>t.label)),['10:00 - 10:45','10:55 - 11:40','12:00 - 12:45','12:55 - 13:40',
  '16:00 - 16:45','16:55 - 17:40','18:00 - 18:45','18:55 - 19:40','20:30 - 21:15','21:25 - 22:10']);
 assert.equal(f.time.ALL_TIMES[4].label,'16:00 - 16:45');
 assert.equal(f.time.ALL_TIMES[7].label,'18:55 - 19:40');
 assert.equal(f.time.ALL_TIMES[8].label,'20:30 - 21:15');
 assert.equal(f.time.courseTimeText('3-4节'),'12:00 – 13:40');
 assert.equal(f.time.courseTimeText('7-8节'),'18:00 – 19:40');
 assert.equal(f.time.courseTimeText('9-10节'),'20:30 – 22:10');
 // 第十小节之后仍是越界：必须解析失败，不能把不存在的节次套到末个时段上
 assert.deepEqual(plain(f.time.parseSections('11-12节')),[0,0]);
});
test('unresolvable sections stay visible instead of disappearing silently',()=>{
 const f=fixture();
 assert.equal(f.time.sectionsResolved('1-2节'),true);
 assert.equal(f.time.sectionsResolved('11-12节'),false);
 assert.equal(f.time.courseTimeText('1-2节'),'10:00 – 11:40');
 assert.equal(f.time.courseTimeText('11-12节'),'节次待确认');
 const legacy=course({day:'星期五',slot:'11-12节',title:'算法设计与分析',sections:'11-12节',weeks:'2-20周(双)'});
 const normal=course({weeks:'1-20周'});
 assert.deepEqual(plain(f.calendar.unresolvedCourses([normal,legacy],6,20).map(c=>c.title)),['算法设计与分析']);
 assert.deepEqual(plain(f.calendar.unresolvedCourses([normal,legacy],7,20).map(c=>c.title)),[]);
 // 时间型功能（今日清单/提醒/桌面/实况窗）仍不登记无法解析的节次，但课本身不会被删掉
 assert.deepEqual(plain(f.calendar.buildOccurrences(snapshot({courses:[legacy]}),new Date(2026,9,16),1)),[]);
});
test('invalid and out-of-range sections never crash or create false times',()=>{
 const f=fixture(); for(const text of ['12-13节','0-2节','1-a节','', '99999999-1']) assert.deepEqual(plain(f.time.parseSections(text)),[0,0]);
});
test('comma, bracket and reversed section lists normalize and retain gaps',()=>{
 const f=fixture(); assert.deepEqual(plain(f.time.sectionNumbers('[2,1,4]')),[1,2,4]);
 assert.deepEqual(plain(f.calendar.courseSectionGroups(course({sections:'1,2,4'}))),[[1,2],[4]]);
 assert.deepEqual(plain(f.time.sectionNumbers('第4–3节')),[3,4]);
});
test('course end boundary is exclusive',()=>{
 const f=fixture(), end=new Date(2026,9,12,9,40); assert.equal(f.time.classStatus(480,580,end),2); assert.equal(f.time.nextClassIndex([{startMinutes:480,endMinutes:580}],end),-1);
});
test('single/double weeks and Chinese separators match actual week',()=>{
 const f=fixture(); assert.equal(f.weeks.isCourseInWeek('1-16周（单）',5),true); assert.equal(f.weeks.isCourseInWeek('1-16周（单）',6),false);
 assert.equal(f.weeks.isCourseInWeek('[2，4，6]',6),true); assert.equal(f.weeks.isCourseInWeek('1-16周双',7),false);
});
test('invalid week labels are excluded and giant ranges are bounded',()=>{
 const f=fixture(); assert.equal(f.weeks.isCourseInWeek('invalid',3),false); assert.equal(f.weeks.isCourseInWeek('1-99999999周',20),true);
});
test('week rollover uses Monday and local calendar dates',()=>{
 const f=fixture(), s=snapshot(); assert.equal(f.calendar.weekOnDate(s,new Date(2026,9,18)),6); assert.equal(f.calendar.weekOnDate(s,new Date(2026,9,19)),7);
 assert.equal(f.calendar.weekOnDate(snapshot({weekKnown:false}),new Date(2026,9,12)),0);
});
test('next week reminders obey odd/even week rules',()=>{
 const f=fixture(), now=new Date(2026,9,18,7), s=snapshot({courses:[course({weeks:'1-20周单'})]});
 const items=f.calendar.buildOccurrences(s,now,7); assert.equal(items.length,1); assert.equal(items[0].week,7); assert.equal(new Date(items[0].startTime).getDate(),19);
});
test('missing week metadata, missing course weeks and unknown times do not schedule',()=>{
 const f=fixture(); assert.equal(f.calendar.buildOccurrences(snapshot({weekKnown:false}),new Date(2026,9,12)).length,0);
 assert.equal(f.calendar.buildOccurrences(snapshot({courses:[course({weeks:''}),course({sections:'12-13节'})]}),new Date(2026,9,12)).length,0);
});
test('duplicate API courses are deduplicated for reminders and rendering',()=>{
 const f=fixture(), courses=[course(),course()]; assert.equal(f.calendar.buildOccurrences(snapshot({courses}),new Date(2026,9,12),1).length,1);
 assert.equal(f.layout.scheduleBlocks(courses,6,20).length,1);
});
test('multi-section courses span rows and conflicting courses use separate lanes',()=>{
 const f=fixture(), blocks=f.layout.scheduleBlocks([course({sections:'1-4节'}),course({title:'物理',sections:'3-4节'})],6,20);
 assert.equal(blocks[0].first,1); assert.equal(blocks[0].last,4); assert.equal(blocks[0].lanes,2); assert.notEqual(blocks[0].lane,blocks[1].lane);
});
test('unrelated courses regain full width after overlapping cluster',()=>{
 const f=fixture(), blocks=f.layout.scheduleBlocks([course(),course({title:'物理'}),course({title:'英语',sections:'5-6节'})],6,20);
 assert.equal(blocks[2].lanes,1);
});
test('widget pause, logout and unknown weeks show no course information',()=>{
 const f=fixture(); assert.equal(f.calendar.widgetData(snapshot({widgetEnabled:false})).courseRoom,'');
 assert.equal(f.calendar.widgetData(null).courseTitle,'打开 APP 同步课表');
 assert.equal(f.calendar.widgetData(snapshot({weekKnown:false})).status,'待校准');
});
test('widget distinguishes no courses today from all courses ended',()=>{
 const f=fixture();
 assert.equal(f.calendar.widgetData(snapshot(),new Date(2026,9,17,12)).status,'今天没有课');
 assert.equal(f.calendar.widgetData(snapshot(),new Date(2026,9,12,23)).status,'今日课程已结束');
 assert.equal(f.calendar.widgetData(snapshot(),new Date(2026,9,12,9)).status,'下一节课');
});
test('widget lesson state observes inclusive start and exclusive end boundaries',()=>{
 const f=fixture(),data=snapshot();
 assert.equal(f.calendar.widgetData(data,new Date(2026,9,12,9,59,59)).status,'下一节课');
 assert.equal(f.calendar.widgetData(data,new Date(2026,9,12,10,0)).status,'上课中');
 assert.equal(f.calendar.widgetData(data,new Date(2026,9,12,11,39,59)).status,'上课中');
 const ended=f.calendar.widgetData(data,new Date(2026,9,12,11,40));
 assert.equal(ended.status,'今日课程已结束');assert.equal(ended.courseRoom,'');assert.equal(ended.courseTime,'');
});
test('unknown companion option never mutates settings or calls native services',async()=>{
 for(const option of ['', 'Live', 'unknown']){
  const f=fixture(),core=await readyCourse(f),before=plain([...f.values]);await assert.rejects(core.setCampusOption(option,true),/选项/);
  assert.deepEqual(plain([...f.values]),before);assert.equal(f.state.liveStarts.length,0);assert.equal(f.state.requests.length,0);
 }
});
test('enabled notifications skip another permission request',async()=>{
 const f=fixture(),core=await readyCourse(f);await core.setCampusOption('reminders',true);
 assert.equal(f.state.notificationRequests||0,0);
});
test('logout during notification preflight cannot reenable course reminders',async()=>{
 const f=fixture(),core=await readyCourse(f),gate=deferred();let entered=false;f.state.notificationQueryHook=async()=>{entered=true;await gate.promise};
 const enable=core.setCampusOption('reminders',true);await until(()=>entered);await core.clearCampusCompanion();gate.resolve();await enable;
 assert.equal(f.values.get('courseReminderEnabled'),false);assert.equal(f.state.requests.length,0);
});
test('logout during live view preflight cannot reenable live switch',async()=>{
 const f=fixture(),core=await readyCourse(f),gate=deferred();let entered=false;f.state.liveQueryHook=async()=>{entered=true;await gate.promise};
 const enable=core.setCampusOption('live',true);await until(()=>entered);await core.clearCampusCompanion();gate.resolve();await enable;
 assert.equal(f.values.get('liveViewEnabled'),false);assert.equal(f.state.liveStarts.length,0);
});
test('closing reminders during permission dialog wins over late grant or denial',async()=>{
 for(const granted of [false,true]){
  const f=fixture(),core=await readyCourse(f),gate=deferred();f.state.notificationAllowed=false;f.state.notificationRequestHook=()=>gate.promise;
  const enable=core.setCampusOption('reminders',true);await until(()=>f.state.notificationRequests===1);await core.setCampusOption('reminders',false);
  f.state.notificationAllowed=granted;gate.resolve();await enable;assert.equal(f.values.get('courseReminderEnabled'),false);assert.equal(f.state.requests.length,0);assert.equal(f.values.get('courseReminderStatus'),'已关闭并取消课程提醒');
 }
});
test('late live disable completion cannot overwrite a newer enabled status',async()=>{
 const f=fixture();f.state.now=new Date(2026,9,12,9,51).getTime();const core=await readyCourse(f);await core.setCampusOption('live',true);
 const gate=deferred();f.state.stopHook=()=>gate.promise;const off=core.setCampusOption('live',false);await until(()=>f.state.liveStops.length>0);
 const on=core.setCampusOption('live',true);await until(()=>f.values.get('liveViewEnabled')===true);gate.resolve();await Promise.all([off,on]);
 assert.equal(f.values.get('liveViewEnabled'),true);assert.notEqual(f.values.get('liveViewStatus'),'已关闭课程实况窗');
});
test('notification denial leaves switch off with no published reminders',async()=>{
 const f=fixture(), core=await readyCourse(f); f.state.notificationAllowed=false;
 await assert.rejects(core.setCampusOption('reminders',true)); assert.equal(f.values.get('courseReminderEnabled'),false); assert.equal(f.state.reminders.size,0);
});
test('system calendar reminder is exactly ten minutes early and opens schedule',async()=>{
 const f=fixture(), core=await readyCourse(f); await core.setCampusOption('reminders',true);
 assert.equal(f.state.reminders.size,1); const request=f.state.requests[0]; assert.deepEqual(plain(request.dateTime),{year:2026,month:10,day:12,hour:9,minute:50});
 assert.equal(request.wantAgent.parameters.campusRoute,'schedule'); assert.equal(f.stores.get('xjit_campus_companion').get('reminders'),true);
});
test('course ten-minute trigger boundary never registers an elapsed calendar time',async()=>{
 for(const offset of [-1,0,1]){
  const f=fixture();f.state.now=new Date(2026,9,12,9,50).getTime()+offset;const core=await readyCourse(f);await core.setCampusOption('reminders',true);
  const today=f.state.requests.filter(r=>r.dateTime.year===2026&&r.dateTime.month===10&&r.dateTime.day===12);
  assert.equal(today.length,offset<0?1:0);if(today.length){assert.equal(today[0].groupId,'campus_courses');assert.equal(today[0].dateTime.minute,50)}
 }
});
test('course reminder skips trigger that elapsed during native group query',async()=>{
 const f=fixture();f.state.now=new Date(2026,9,12,9,49,59).getTime();const core=await readyCourse(f);
 f.state.allValidHook=async()=>{f.state.now=new Date(2026,9,12,9,50,1).getTime()};await core.setCampusOption('reminders',true);
 assert.equal(f.state.requests.filter(r=>r.dateTime.day===12).length,0);
});
test('course reminder rechecks later items after slow native publication',async()=>{
 const f=fixture(),core=await readyCourse(f,[course(),course({sections:'3-4节',title:'Later course'})]);
 f.state.publishHook=async()=>{f.state.now=new Date(2026,9,12,12,0).getTime()};await core.setCampusOption('reminders',true);
 const today=f.state.requests.filter(r=>r.dateTime.day===12);assert.equal(today.length,1);assert.ok(today[0].title.includes('高等数学'));
});
test('turning reminders off cancels native reminders and persists switch',async()=>{
 const f=fixture(), core=await readyCourse(f);await core.setCampusOption('reminders',true);await core.setCampusOption('reminders',false);
 assert.equal(f.state.reminders.size,0);assert.equal(f.stores.get('xjit_campus_companion').get('reminders'),false);
});
test('switching off during native publication cancels the late reminder',async()=>{
 const f=fixture(), core=await readyCourse(f), gate=deferred();f.state.publishHook=()=>gate.promise;
 const enabled=core.setCampusOption('reminders',true);await until(()=>f.state.requests.length===1);
 const disabled=core.setCampusOption('reminders',false);await until(()=>f.values.get('courseReminderEnabled')===false);gate.resolve();await Promise.all([enabled,disabled]);
 assert.equal(f.state.reminders.size,0);
});
test('retired course publication failure cannot disable a newer enable request',async()=>{
 const f=fixture(),core=await readyCourse(f),gate=deferred();f.state.publishHook=async()=>{await gate.promise;throw Error('retired publication failure')};
 const first=core.setCampusOption('reminders',true);await until(()=>f.state.requests.length===1);
 const second=core.setCampusOption('reminders',true);await Promise.resolve();await Promise.resolve();f.state.publishHook=null;gate.resolve();
 await Promise.allSettled([first,second]);assert.equal(f.values.get('courseReminderEnabled'),true);assert.equal(f.state.reminders.size,1);
});
test('logout survives late course publication errors and preserves todo group',async()=>{
 for(const code of [401,1700002]){
  const f=fixture(),core=await readyCourse(f),gate=deferred();f.state.reminders.set(9999,{groupId:'campus_todos'});
  f.state.publishHook=async()=>{await gate.promise;throw {code}};const enable=core.setCampusOption('reminders',true);await until(()=>f.state.requests.length===1);
  const clear=core.clearCampusCompanion();gate.resolve();await Promise.allSettled([enable,clear]);
  assert.equal(f.values.get('courseReminderEnabled'),false);assert.equal(f.values.get('courseReminderStatus'),'已关闭并取消课程提醒');assert.equal(f.state.reminders.size,1);assert.equal(f.state.reminders.get(9999).groupId,'campus_todos');
 }
});
test('logout cancels reminders, clears widget snapshot and rejects stale schedule',async()=>{
 const f=fixture(), core=await readyCourse(f);await core.setCampusOption('widget',true);await core.setCampusOption('reminders',true);
 const cache=f.get('services/MemoryCache');await cache.clearAllCachedValues();await core.clearCampusCompanion();
 await core.acceptCampusSchedule('test-student',{term:'old',courses:[course()],currentWeek:6},0);
 assert.equal(f.state.reminders.size,0);assert.equal(f.disks.get('/data/campus_widget.json'),'null');assert.equal(core.getCampusWidgetData().courseRoom,'');
});
test('week calibration persists and the same cached response cannot reset it',async()=>{
 const f=fixture(), core=await readyCourse(f,[course()],{currentWeek:undefined});assert.equal(f.values.get('scheduleWeekKnown'),false);
 await core.calibrateCampusWeek(8);await core.acceptCampusSchedule('test-student',{term:'2026-2027-1',courses:[course()],scheduleFetchedAt:f.state.now},0);
 assert.equal(f.values.get('currentWeek'),8); assert.equal(JSON.parse(f.disks.get('/data/campus_widget.json')).weekKnown,true);
});
test('fresh calendar cannot overwrite manual calibration but new term resets it',async()=>{
 const f=fixture(),core=await readyCourse(f); await core.calibrateCampusWeek(8);
 await core.acceptCampusSchedule('test-student',{term:'2026-2027-1',courses:[course()],termStartDate:'2026-08-31',totalWeeks:19,scheduleFetchedAt:f.state.now+1},0);
 assert.equal(f.values.get('currentWeek'),8);
 await core.acceptCampusSchedule('test-student',{term:'2026-2027-2',courses:[course()],scheduleFetchedAt:f.state.now+2},0);
 assert.equal(f.values.get('scheduleWeekKnown'),false);
});
test('shortened semester invalidates out-of-range inherited calibration without corrupting snapshot',async()=>{
 const f=fixture(),core=await readyCourse(f);await core.calibrateCampusWeek(18);
 await core.acceptCampusSchedule('test-student',{term:'2026-2027-1',courses:[course()],totalWeeks:16,scheduleFetchedAt:f.state.now+1},0);
 const saved=f.get('services/WidgetService').readWidgetSnapshot({filesDir:'/data'});
 assert.ok(saved);assert.equal(saved.totalWeeks,16);assert.equal(saved.weekKnown,false);
 assert.equal(saved.manuallyCalibrated,false);assert.equal(saved.currentWeek,1);
});
test('shorter semester retains valid manual week and adopts source week after invalid calibration',async()=>{
 for(const [oldWeek,expected,manual] of [[8,8,true],[18,7,false]]){
  const f=fixture(),core=await readyCourse(f);await core.calibrateCampusWeek(oldWeek);
  await core.acceptCampusSchedule('test-student',{term:'2026-2027-1',courses:[course()],totalWeeks:16,currentWeek:7,scheduleFetchedAt:f.state.now+1},0);
  const saved=f.get('services/WidgetService').readWidgetSnapshot({filesDir:'/data'});
  assert.ok(saved);assert.equal(saved.currentWeek,expected);assert.equal(saved.weekKnown,true);assert.equal(saved.manuallyCalibrated,manual);
 }
});
test('companion ignores invalid semester totals consistently with schedule page',async()=>{
 for(const totalWeeks of [Infinity,NaN,0,-1,1.5,61,999]){
  const f=fixture();await readyCourse(f,[course()],{totalWeeks});
  assert.equal(f.get('services/WidgetService').readWidgetSnapshot({filesDir:'/data'}).totalWeeks,20);
 }
});
test('companion semester total accepts bounds alternate field and retains valid prior term total',async()=>{
 for(const [data,total] of [[{totalWeeks:1,currentWeek:1},1],[{totalWeeks:60},60],[{totalWeeks:Infinity,weeksTotal:19},19]]){
  const f=fixture();await readyCourse(f,[course()],data);
  assert.equal(f.get('services/WidgetService').readWidgetSnapshot({filesDir:'/data'}).totalWeeks,total);
 }
 const f=fixture(),core=await readyCourse(f,[course()],{totalWeeks:18});f.state.now+=1000;
 await core.acceptCampusSchedule('test-student',{term:'2026-2027-1',courses:[course()],totalWeeks:Infinity,scheduleFetchedAt:f.state.now},0);
 assert.equal(f.get('services/WidgetService').readWidgetSnapshot({filesDir:'/data'}).totalWeeks,18);
});
test('snapshot read boundary rejects invalid shape and week metadata',()=>{
 const f=fixture(),widgets=f.get('services/WidgetService'),ctx={filesDir:'/data'};
 for(const value of [{},snapshot({courses:[null]}),snapshot({courses:[course({weeks:12})]}),snapshot({totalWeeks:1.5}),snapshot({currentWeek:99}),snapshot({widgetEnabled:'yes'})]){
  f.disks.set('/data/campus_widget.json',JSON.stringify(value));assert.equal(widgets.readWidgetSnapshot(ctx),null);
 }
 f.disks.set('/data/campus_widget.json',JSON.stringify(snapshot()));assert.ok(widgets.readWidgetSnapshot(ctx));
});
test('malformed persisted snapshot renders pending widget instead of crashing',()=>{
 const f=fixture(),widgets=f.get('services/WidgetService'),ctx={filesDir:'/data'};
 for(const value of [{}, {account:null}, snapshot({courses:null}),snapshot({courses:[null]})]){
  f.disks.set('/data/campus_widget.json',JSON.stringify(value));
  assert.equal(widgets.buildWidgetBinding(ctx).data.status,'待同步');
 }
});
test('snapshot write and rename failures preserve last complete disk snapshot',async()=>{
 for(const failure of ['writeFail','renameFail']){
  const f=fixture();await readyCourse(f);const widgets=f.get('services/WidgetService'),ctx={filesDir:'/data'};
  const before=JSON.stringify(widgets.readWidgetSnapshot(ctx));const closed=f.state.closedFiles||0;
  f.state[failure]=true;assert.throws(()=>widgets.saveWidgetSnapshot(ctx,null));
  assert.equal(JSON.stringify(widgets.readWidgetSnapshot(ctx)),before);assert.equal(f.state.closedFiles,closed+1);
  f.state[failure]=false;widgets.saveWidgetSnapshot(ctx,null);assert.equal(widgets.readWidgetSnapshot(ctx),null);
 }
});
test('manual week marker and anchor survive snapshot disk roundtrip',async()=>{
 const f=fixture(),core=await readyCourse(f); await core.calibrateCampusWeek(8);
 const restored=f.get('services/WidgetService').readWidgetSnapshot({filesDir:'/data'});
 assert.equal(restored.manuallyCalibrated,true); assert.equal(restored.currentWeek,8); assert.equal(restored.anchorDate,'2026-10-12');
 await core.acceptCampusSchedule('test-student',{term:'2026-2027-1',courses:[course()],currentWeek:7,totalWeeks:19,scheduleFetchedAt:f.state.now+1},0);
 assert.equal(f.values.get('currentWeek'),8);
});
test('manual calibration rejects fractional and nonfinite weeks without mutation',async()=>{
 const f=fixture(),core=await readyCourse(f);
 for(const week of [NaN,Infinity,1.5]) await assert.rejects(core.calibrateCampusWeek(week));
 assert.equal(f.values.get('currentWeek'),6);
});
test('reminder registration is capped to leave system capacity',async()=>{
 const f=fixture(), courses=[];for(let day=1;day<=7;day++)for(let n=1;n<=10;n++)courses.push(course({day:String(day),sections:String(n),title:'课程'+day+'-'+n}));
 const core=await readyCourse(f,courses);await core.setCampusOption('reminders',true);assert.equal(f.state.reminders.size,24);
 assert.match(f.values.get('courseReminderStatus'),/已登记最近 24 条/);assert.match(f.values.get('courseReminderStatus'),/打开 APP 自动续订/);
});
test('system reminder quota preserves already registered courses',async()=>{
 const f=fixture();const core=await readyCourse(f,[course(),course({sections:'3-4节',title:'second'})]);
 let attempts=0;f.state.publishHook=async()=>{if(++attempts>1)throw {code:1700002};};
 await core.setCampusOption('reminders',true);
 assert.equal(f.state.reminders.size,1);assert.equal(f.values.get('courseReminderEnabled'),true);
   assert.match(f.values.get('courseReminderStatus'),/系统提醒条数已达上限/);
 assert.ok(!f.values.get('courseReminderStatus').includes('检查通知权限'));
});
test('quota status uses native reminder count without assuming zero on query failure',async()=>{
 for(const fails of [false,true]){
  const f=fixture(),core=await readyCourse(f);f.state.validQueryFails=fails;
  f.state.publishHook=async()=>{throw {code:1700002};};
  await core.setCampusOption('reminders',true);
  assert.ok(f.values.get('courseReminderStatus').includes(fails?'本应用登记数量读取失败':'本应用登记数量 0 条'));
 }
});
test('returning to app retries a quota-limited plan after capacity recovers',async()=>{
 const f=fixture(),core=await readyCourse(f,[course(),course({sections:'3-4节',title:'second'})]);
 f.state.publishHook=async()=>{throw {code:1700002};};
 await core.setCampusOption('reminders',true); assert.equal(f.state.reminders.size,0);
 f.state.publishHook=null; await core.activateCampusCompanion('test-student');
 assert.equal(f.state.reminders.size,2); assert.match(f.values.get('courseReminderStatus'),/已登记未来 7 天 2 条/);
 await core.setCampusOption('reminders',false); assert.equal(f.state.reminders.size,0);
});
test('invalid reminder parameters are not reported as notification permission failure',async()=>{
 const f=fixture(),core=await readyCourse(f); f.state.publishHook=async()=>{throw {code:401};};
 await assert.rejects(core.setCampusOption('reminders',true));
 assert.match(f.values.get('courseReminderStatus'),/提醒参数无效/);
 assert.equal(f.values.get('courseReminderEnabled'),false);
});
test('reminder failures distinguish permission notification and unknown errors and clean partial records',async()=>{
 for(const [code,text] of [[201,'提醒权限未授予（201）'],[1700001,'系统通知尚未开启（1700001）'],[999999,'提醒登记失败（999999），请稍后重试']]){
  const f=fixture(),core=await readyCourse(f,[course(),course({sections:'3-4节',title:'second'})]);
  let attempts=0;f.state.publishHook=async()=>{if(++attempts>1)throw {code};};
  await assert.rejects(core.setCampusOption('reminders',true));
  assert.equal(f.values.get('courseReminderStatus'),text);
  assert.equal(f.values.get('courseReminderEnabled'),false); assert.equal(f.state.reminders.size,0);
 }
});
test('real LiveView payload uses TIMER and millisecond duration',async()=>{
 const f=fixture();f.state.now=new Date(2026,9,12,9,51).getTime();const core=await readyCourse(f);await core.setCampusOption('live',true);
 assert.equal(f.state.liveStarts.length,1);const view=f.state.liveStarts[0];assert.equal(view.event,'TIMER');assert.equal(view.timer.time,9*60000);
 assert.equal(view.liveViewData.capsule.type,2);assert.equal(view.liveViewData.primary.clickAction.options.wants[0].parameters.campusRoute,'schedule');
});
test('HarmonyOS 6.0 live view carries the dynamic island tail affordances',async()=>{
 const f=fixture();f.state.sdkApiVersion=20;f.state.now=new Date(2026,9,12,9,51).getTime();
 const core=await readyCourse(f);await core.setCampusOption('live',true);
 const capsule=f.state.liveStarts[0].liveViewData.capsule;
 assert.equal(capsule.icon,'liveview_capsule.png');
 assert.equal(capsule.tailIcon,'liveview_capsule.png');
 assert.equal(capsule.isContentDisplayed,true);
 assert.equal(capsule.isTailIconDisplayed,true);
});
test('live view before API 20 omits only the tail members that do not exist yet',async()=>{
 // The tail affordances (tailIcon, isTailIconDisplayed) are @since 6.0.0(20);
 // the plain capsule icon is @since 4.1.0(11) and stays available below that.
 const f=fixture();f.state.sdkApiVersion=19;f.state.now=new Date(2026,9,12,9,51).getTime();
 const core=await readyCourse(f);await core.setCampusOption('live',true);
 const capsule=f.state.liveStarts[0].liveViewData.capsule;
 assert.equal(capsule.tailIcon,undefined);
 assert.equal(capsule.isTailIconDisplayed,undefined);
 assert.notEqual(capsule.icon,undefined);
 assert.equal(capsule.isContentDisplayed,true);
});
test('live view fixed area uses the system timer placeholder so the island ticks itself',async()=>{
 const f=fixture();f.state.now=new Date(2026,9,12,9,51).getTime();
 const core=await readyCourse(f);await core.setCampusOption('live',true);
 const content=f.state.liveStarts[0].liveViewData.primary.content;
 // The placeholder must sit inside a single text string. The system resolves it
 // per string; a separate array entry has no timer context to resolve against and
 // renders as unresolved text instead of the remaining time.
 assert.equal(content.length,1,'the fixed area must carry exactly one text entry');
 assert.ok(content[0].text.includes('${placeholder.timer}'),'the placeholder must be present');
 assert.ok(content[0].text.length<128,'the text must stay within the 128 character limit');
});
test('the timer placeholder is never a standalone content entry',async()=>{
 const f=fixture();f.state.now=new Date(2026,9,12,9,51).getTime();
 const core=await readyCourse(f);await core.setCampusOption('live',true);
 const content=f.state.liveStarts[0].liveViewData.primary.content;
 for(const part of content){
  assert.ok(!/^\s*\$\{placeholder\.timer\}\s*$/.test(part.text),'the placeholder must not stand alone');
 }
});
test('the countdown reaches a preset ending instead of a raw zero',async()=>{
 const f=fixture();f.state.sdkApiVersion=26;f.state.now=new Date(2026,9,12,9,51).getTime();
 const core=await readyCourse(f);await core.setCampusOption('live',true);
 const timer=f.state.liveStarts[0].timer;
 assert.ok(timer.countdownPreset,'a preset ending is required from API 20');
 assert.ok(timer.countdownPreset.presetTitle.length>0);
 assert.ok(timer.countdownPreset.presetContent.length>0);
 assert.ok(timer.capsuleCountdownPreset,'the capsule needs its own preset ending');
});
test('capsule keeps its island affordances when the course switches to 上课中',async()=>{
 const f=fixture();f.state.sdkApiVersion=20;f.state.now=new Date(2026,9,12,9,51).getTime();
 f.values.set('liveViewEnabled',true);
 const live=f.get('services/LiveViewService');
 const start=f.state.now+60000;
 const target={type:'course',title:'算法',text:'1-2节',extra:'B306',startTime:start,endTime:start+3600000};
 await live.startLiveView(target);
 assert.equal(f.state.liveStarts.length,1);
 assert.equal(f.state.liveStarts[0].liveViewData.capsule.content,'距上课');
 // The clock moves past the class start while the target identity stays the same,
 // so the service must flip the existing capsule instead of recreating the view.
 f.state.now=start+1000;
 await live.startLiveView(target);
 assert.equal(f.state.liveUpdates.length,1);
 assert.equal(f.state.liveStops.length,0,'a running island must not be torn down at class start');
 const updated=f.state.liveUpdates[0].liveViewData.capsule;
 assert.equal(updated.content,'上课中');
 assert.equal(updated.icon,'liveview_capsule.png');
 assert.equal(updated.tailIcon,'liveview_capsule.png');
 assert.equal(updated.isTailIconDisplayed,true);
});
test('enabled LiveView registers the next class immediately instead of waiting for a ten-minute gate',async()=>{
 const f=fixture(),core=await readyCourse(f);await core.setCampusOption('live',true);
 // 系统触发式实况窗只支持地理围栏、没有时间触发，所以"到点自动弹"在 API 23/24 上
 // 做不到。改成当天有课就登记，倒计时一路走到上课，用户不必卡着课前十分钟再开 App。
 assert.equal(f.state.liveStarts.length,1);
 assert.match(String(f.values.get('liveViewStatus')),/^实况窗已显示/);
 f.state.now=new Date(2026,9,12,9,51).getTime();await core.activateCampusCompanion('test-student');
 assert.equal(f.state.liveStarts.length,1);assert.match(String(f.values.get('liveViewStatus')),/^实况窗已显示/);
 f.state.now=new Date(2026,9,12,12,0).getTime();await core.activateCampusCompanion('test-student');
 assert.equal(f.state.liveStops.length,1);assert.equal(f.values.get('liveViewStatus'),'已开启，今天暂无后续课程');
 await core.setCampusOption('live',false);assert.equal(f.values.get('liveViewStatus'),'已关闭课程实况窗');
 const g=fixture(),pending=await g.boot();await pending.setCampusOption('live',true);
 assert.equal(g.values.get('liveViewStatus'),'已开启，等待课表同步和当前周次校准');assert.equal(g.state.liveStarts.length,0);
});
test('missing abilityInfo at emulator startup still resolves the launched bundle safely',async()=>{
 const f=fixture(),core=f.get('services/CampusCompanionService');await core.initCampusCompanion({filesDir:'/data'},'com.xjit.app.designreview');assert.equal(core.getCampusBundleName(),'com.xjit.app.designreview');
 const g=fixture(),fallback=g.get('services/CampusCompanionService');await fallback.initCampusCompanion({filesDir:'/data',applicationInfo:{name:'com.xjit.app.acceptance'}});assert.equal(fallback.getCampusBundleName(),'com.xjit.app.acceptance');
 const h=fixture(),formal=h.get('services/CampusCompanionService');await formal.initCampusCompanion({filesDir:'/data'});assert.equal(formal.getCampusBundleName(),'com.xjit.app');
});
test('reminder taps return to the running app bundle and course schedule',async()=>{
 const f=fixture();f.state.bundleName='com.xjit.app.designreview';const core=await readyCourse(f);await core.setCampusOption('reminders',true);
 assert.ok(f.state.requests.length>0);for(const request of f.state.requests){assert.equal(request.wantAgent.pkgName,f.state.bundleName);assert.equal(request.wantAgent.abilityName,'EntryAbility');assert.equal(request.wantAgent.parameters.campusRoute,'schedule');}
});
test('LiveView taps return to the running app bundle and course schedule',async()=>{
 const f=fixture();f.state.bundleName='com.xjit.app.acceptance';f.state.now=new Date(2026,9,12,9,51).getTime();const core=await readyCourse(f);await core.setCampusOption('live',true);
 assert.equal(f.state.liveStarts.length,1);const action=f.state.liveStarts[0].liveViewData.primary.clickAction.options.wants[0];assert.equal(action.bundleName,f.state.bundleName);assert.equal(action.abilityName,'EntryAbility');assert.equal(action.parameters.campusRoute,'schedule');
});
test('changed live view deadline replaces the old timer',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService'),target={type:'todo',todoId:'task',title:'Study',text:'',extra:'',startTime:f.clock.now(),endTime:f.clock.now()+3600000};
 await live.startLiveView(target);await live.startLiveView({...target,endTime:target.endTime+3600000});
 assert.equal(f.state.liveStarts.length,2);assert.equal(f.state.liveStarts[1].timer.time,7200000);
});
test('same-tick live view instances have distinct system ids and reject old handles',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService'),item={id:'a',title:'Study',note:'',dueText:'',done:false,createdAt:1,updatedAt:1};
 const first=await live.startTodoLiveView(item),second=await live.startTodoLiveView({...item,id:'b'});
 assert.notEqual(first.handle.id,second.handle.id);const stops=f.state.liveStops.length;
 await live.finishLiveView(first.handle);assert.equal(f.state.liveStops.length,stops);assert.equal(live.getCurrentHandle().id,second.handle.id);
});
test('todo native live view capsule never uses class wording',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService');
 await live.startTodoLiveView({id:'task',title:'Study',note:'',dueText:'',done:false,createdAt:1,updatedAt:1});
 assert.equal(f.state.liveStarts[0].liveViewData.capsule.content,'待办计时');
});
test('same-title todo live views retain distinct task identities',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService');const a={id:'a',title:'Study',note:'',dueText:'',done:false,createdAt:1,updatedAt:1},b={...a,id:'b'};
 await live.startTodoLiveView(a);await live.startTodoLiveView(b);assert.equal(f.state.liveStarts.length,2);
 const stops=f.state.liveStops.length;await live.reconcileTodoLiveView([{...a,done:true},b]);assert.equal(f.state.liveStops.length,stops);
 await live.reconcileTodoLiveView([a]);assert.equal(f.state.liveStops.length,stops+1);
});
test('todo reconciliation ends only the completed or deleted active task',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService');const item={id:'task',title:'Study',note:'',dueText:'',done:false,createdAt:1,updatedAt:1};
 await live.startTodoLiveView(item);await live.reconcileTodoLiveView([item]);assert.equal(f.state.liveStops.length,0);
 await live.reconcileTodoLiveView([{...item,done:true}]);assert.equal(f.state.liveStops.length,1);
 await live.startTodoLiveView(item);await live.reconcileTodoLiveView([]);assert.equal(f.state.liveStops.length,2);
 await live.startCourseLiveView(course(),f.clock.now(),f.clock.now()+3600000);await live.reconcileTodoLiveView([]);assert.equal(f.state.liveStops.length,2);
});
test('failed live view stop preserves active content for later retry',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService');
 const started=await live.startCourseLiveView(course(),f.clock.now(),f.clock.now()+3600000);f.state.stopFail=true;
 await assert.rejects(live.finishLiveView(started.handle));f.state.stopFail=false;
 await live.updateLiveView(started.handle,course(),f.clock.now());const updated=f.state.liveUpdates[0];
 assert.equal(updated.liveViewData.capsule.status,f.state.liveStarts[0].liveViewData.capsule.status);
 assert.equal(updated.liveViewData.primary.keepTime,f.state.liveStarts[0].liveViewData.primary.keepTime);
 await live.finishLiveView(started.handle);assert.equal(live.getCurrentHandle(),null);
});
test('failed live view title update restores committed content and reports failure',async()=>{
 for(const thrown of [false,true]){
  const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService'),original=course();
  const started=await live.startCourseLiveView(original,f.clock.now(),f.clock.now()+3600000);
  if(thrown)f.state.updateError={code:1003500003};else f.state.updateCode=4;
  await assert.rejects(live.updateLiveView(started.handle,{...original,title:'Failed title'},f.clock.now()));
  await live.finishLiveView(started.handle);assert.equal(f.state.liveStops[0].liveViewData.primary.title,original.title);
  assert.ok(live.getLiveViewSupportReason().includes('失败')||live.getLiveViewSupportReason().includes('服务'));
 }
});
test('queued course live view update preserves the submitted title',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService');
 const started=await live.startCourseLiveView(course(),f.clock.now(),f.clock.now()+3600000);const changed=course();changed.title='Original';
 const pending=live.updateLiveView(started.handle,changed,f.clock.now());changed.title='Mutated';await pending;
 assert.equal(f.state.liveUpdates[0].liveViewData.primary.title,'Original');
});
test('live view handles returned to callers never expose internal identity',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService');
 const result=await live.startCourseLiveView(course(),f.clock.now(),f.clock.now()+3600000);const original={...result.handle};
 result.handle.id='changed';assert.equal(live.getCurrentHandle().id,original.id);
 const exposed=live.getCurrentHandle();exposed.startTime=0;assert.equal(live.getCurrentHandle().startTime,original.startTime);
 await live.finishLiveView(original);assert.equal(live.getCurrentHandle(),null);
});
test('stale live view handles cannot update or finish a newer instance',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService');
 const first=await live.startCourseLiveView(course(),f.clock.now(),f.clock.now()+3600000);
 const second=await live.startCourseLiveView(course(),f.clock.now()+60000,f.clock.now()+7200000);
 const stops=f.state.liveStops.length;await live.updateLiveView(first.handle,course(),f.clock.now());await live.finishLiveView(first.handle);
 assert.equal(f.state.liveUpdates.length,0);assert.equal(f.state.liveStops.length,stops);assert.equal(live.getCurrentHandle().startTime,second.handle.startTime);
 await live.finishLiveView(second.handle);assert.equal(f.state.liveStops.length,stops+1);
});
test('queued live view target preserves caller snapshot',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService');const target={type:'todo',title:'Original',text:'',extra:'',startTime:f.clock.now(),endTime:f.clock.now()+3600000};
 const pending=live.startLiveView(target);target.endTime=0;const result=await pending;assert.equal(result.ok,true);assert.equal(f.state.liveStarts.length,1);
});
test('capsule members are gated by the API level that introduced them',async()=>{
 // icon is @since 11, isContentDisplayed @since 15, tailIcon / isTailIconDisplayed @since 20.
 const expected={11:{icon:true,isContentDisplayed:false,tailIcon:false},
  15:{icon:true,isContentDisplayed:true,tailIcon:false},
  20:{icon:true,isContentDisplayed:true,tailIcon:true},
  26:{icon:true,isContentDisplayed:true,tailIcon:true}};
 for(const [api,want] of Object.entries(expected)){
  const f=fixture();f.state.sdkApiVersion=Number(api);f.values.set('liveViewEnabled',true);
  const live=f.get('services/LiveViewService');
  await live.startLiveView({type:'todo',title:'Study',text:'',extra:'',startTime:f.clock.now(),endTime:f.clock.now()+3600000});
  const c=f.state.liveStarts[0].liveViewData.capsule;
  assert.equal(c.icon!==undefined,want.icon,`api ${api} icon`);
  assert.equal(c.isContentDisplayed!==undefined,want.isContentDisplayed,`api ${api} isContentDisplayed`);
  assert.equal(c.tailIcon!==undefined,want.tailIcon,`api ${api} tailIcon`);
  assert.equal(c.isTailIconDisplayed!==undefined,want.tailIcon,`api ${api} isTailIconDisplayed`);
 }
});
test('live view timer is only set on API 12 and above',async()=>{
 for(const [api,wantTimer] of [[11,false],[12,true],[26,true]]){
  const f=fixture();f.state.sdkApiVersion=Number(api);f.values.set('liveViewEnabled',true);
  const live=f.get('services/LiveViewService');
  await live.startLiveView({type:'todo',title:'Study',text:'',extra:'',startTime:f.clock.now(),endTime:f.clock.now()+3600000});
  assert.equal(f.state.liveStarts[0].timer!==undefined,wantTimer,`api ${api} timer`);
 }
});
test('a refused live view update rolls the system version back',async()=>{
 const f=fixture();f.state.sdkApiVersion=26;f.values.set('liveViewEnabled',true);
 const live=f.get('services/LiveViewService');
 const started=await live.startCourseLiveView(course(),f.clock.now(),f.clock.now()+3600000);
 const created=f.state.liveStarts[0].sequence;
 // The system refuses the update, so its own version stays where it was.
 f.state.updateCode=1;
 await assert.rejects(live.updateLiveView(started.handle,course(),f.clock.now()));
 f.state.updateCode=0;
 // A later retry must still be accepted, which requires the local counter to be
 // back in step with the system instead of having skipped a version.
 await live.updateLiveView(started.handle,course({title:'Retried'}),f.clock.now());
 assert.equal(f.state.liveUpdates[0].sequence,created+1,'retry must reuse the next version');
});
 test('a stop that reports already ended is treated as done, not retried forever',async()=>{
  // 1003500009 表示实况窗不存在、1003500010 表示已结束。这两种情况下系统侧
  // 本来就没有窗口了，若当成普通失败回滚并抛错，本地会一直卡在一个已经不存在的
  // 窗口上，每次登出都重试一遍。
  for(const code of [1003500009,1003500010]){
     const f=fixture();f.state.sdkApiVersion=26;f.values.set('liveViewEnabled',true);
     const live=f.get('services/LiveViewService');
   const started=await live.startCourseLiveView(course(),f.clock.now(),f.clock.now()+3600000);
   f.state.stopFail=true;f.state.stopFailCode=code;
   await live.finishLiveView(started.handle);
   assert.equal(live.getCurrentHandle(),null,'the local handle must be released for '+code);
   f.state.stopFail=false;f.state.stopFailCode=undefined;
  }
 });
test('a refused live view stop rolls the system version back',async()=>{
 const f=fixture();f.state.sdkApiVersion=26;f.values.set('liveViewEnabled',true);
 const live=f.get('services/LiveViewService');
 const started=await live.startCourseLiveView(course(),f.clock.now(),f.clock.now()+3600000);
 const created=f.state.liveStarts[0].sequence;
 f.state.stopFail=true;
 await assert.rejects(live.finishLiveView(started.handle));
 f.state.stopFail=false;
 await live.finishLiveView(started.handle);
 assert.equal(f.state.liveStops[0].sequence,created+1,'a retried stop must reuse the next version');
});
test('the class-start transition rolls the system version back when refused',async()=>{
 const f=fixture();f.state.sdkApiVersion=26;f.values.set('liveViewEnabled',true);
 const live=f.get('services/LiveViewService');
 const start=f.clock.now()+60000;
 const target={type:'course',title:'算法',text:'1-2节',extra:'B306',startTime:start,endTime:start+3600000};
 await live.startLiveView(target);
 const created=f.state.liveStarts[0].sequence;
 f.state.now=start+1000;
 f.state.updateCode=1;
 await live.startLiveView(target);
 f.state.updateCode=0;
 f.state.now=start+2000;
 await live.startLiveView(target);
 assert.equal(f.state.liveUpdates[1].sequence,created+1,'the retry must not skip a version');
});
test('todo live target uses structured deadline rather than fabricated one hour',()=>{
 const f=fixture(),live=f.get('services/LiveViewService'),item={id:'task',title:'Study',note:'',dueText:'',dueAt:f.clock.now()+7200000,done:false,createdAt:1,updatedAt:1};
 assert.equal(live.buildTodoLiveTarget(item).endTime,item.dueAt);
 assert.equal(live.buildTodoLiveTarget({...item,dueAt:undefined}).endTime,f.clock.now()+3600000);
});
test('invalid live view times never reach the native service',async()=>{
 for(const endTime of [NaN,Infinity,8640000000000001]){
  const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService');
  const result=await live.startLiveView({type:'todo',title:'Study',text:'',extra:'',startTime:f.clock.now(),endTime});assert.equal(result.ok,false);assert.equal(f.state.liveStarts.length,0);
 }
});
test('completed todo cannot start a native live view',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService');
 const result=await live.startTodoLiveView({id:'done',title:'Finished',note:'',dueText:'',done:true,createdAt:1,updatedAt:1});
 assert.equal(result.ok,false);assert.ok(result.reason.includes('已完成'));assert.equal(f.state.liveStarts.length,0);
});
test('LiveView permission denial is reported and never presented as success',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);f.state.liveError={code:1003500005};const live=f.get('services/LiveViewService');
 const result=await live.startCourseLiveView(course(),f.state.now+60000,f.state.now+3600000);
 assert.equal(result.ok,false);assert.match(result.reason,/尚未获批/);assert.equal(live.getCurrentHandle(),null);
});
test('partial LiveView result is cleaned up and is not success',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);f.state.liveCode=4;const live=f.get('services/LiveViewService');
 const result=await live.startCourseLiveView(course(),f.state.now+60000,f.state.now+3600000);assert.equal(result.ok,false);assert.equal(f.state.liveStops.length,1);
});
test('minute-of-day values are rejected by real LiveView adapter',async()=>{
 const f=fixture();f.values.set('liveViewEnabled',true);const result=await f.get('services/LiveViewService').startCourseLiveView(course(),480,580);
 assert.equal(result.ok,false);assert.equal(f.state.liveStarts.length,0);
});
test('failed class-start transition remains retryable',async()=>{
 for(const thrown of [false,true]){
  const f=fixture();f.values.set('liveViewEnabled',true);const live=f.get('services/LiveViewService'),start=f.clock.now()+60000,end=start+3600000;
  await live.startCourseLiveView(course(),start,end);f.state.now=start+1000;
  if(thrown)f.state.updateError={code:1003500003};else f.state.updateCode=4;
  assert.equal((await live.startCourseLiveView(course(),start,end)).ok,false);
  f.state.updateError=null;f.state.updateCode=0;
  assert.equal((await live.startCourseLiveView(course(),start,end)).ok,true);assert.equal(f.state.liveUpdates.length,2);
 }
});
test('course LiveView changes timer at class start and stops on switch off',async()=>{
 const f=fixture();f.state.now=new Date(2026,9,12,9,51).getTime();const core=await readyCourse(f);await core.setCampusOption('live',true);
 f.state.now=new Date(2026,9,12,10,1).getTime();await core.activateCampusCompanion('test-student');assert.equal(f.state.liveUpdates.length,1);
 assert.equal(f.state.liveUpdates[0].liveViewData.capsule.content,'上课中');assert.match(String(f.values.get('liveViewStatus')),/^实况窗已显示/);
 await core.activateCampusCompanion('test-student');assert.match(String(f.values.get('liveViewStatus')),/^实况窗已显示/);
 await core.setCampusOption('live',false);assert.equal(f.state.liveStops.length,1);
});
test('logout reminder cancellation failure keeps widget private and allows group-specific retry',async()=>{
 const f=fixture(),core=await readyCourse(f);await core.setCampusOption('widget',true);await core.setCampusOption('reminders',true);f.state.reminders.set(9999,{groupId:'campus_todos'});
 f.state.cancelReminderFail=true;await assert.rejects(core.clearCampusCompanion(),/reminder cancel failed/);assert.equal(f.disks.get('/data/campus_widget.json'),'null');assert.equal(f.values.get('courseReminderEnabled'),false);assert.equal(f.state.reminders.size,2);
 f.state.cancelReminderFail=false;await core.clearCampusCompanion();assert.equal(f.state.reminders.size,1);assert.equal(f.state.reminders.get(9999).groupId,'campus_todos');
});
test('preference flush failure during logout still clears widget and reminders',async()=>{
 const f=fixture(),core=await readyCourse(f);await core.setCampusOption('widget',true);await core.setCampusOption('reminders',true);
 f.state.preferenceFlushFail=true;await assert.rejects(core.clearCampusCompanion(),/preference flush failed/);assert.equal(f.state.reminders.size,0);assert.equal(f.disks.get('/data/campus_widget.json'),'null');
 f.state.preferenceFlushFail=false;await core.clearCampusCompanion();
});
test('widget disk failure during logout does not leave course reminders registered',async()=>{
 const f=fixture(),core=await readyCourse(f);await core.setCampusOption('reminders',true);assert.equal(f.state.reminders.size,1);
 f.state.writeFail=true;await assert.rejects(core.clearCampusCompanion());assert.equal(f.state.reminders.size,0);f.state.writeFail=false;await core.clearCampusCompanion();assert.equal(f.disks.get('/data/campus_widget.json'),'null');
});
test('combined logout failures still cancel reminders and recover on retry',async()=>{
 const f=fixture(),core=await readyCourse(f);await core.setCampusOption('reminders',true);f.state.now=new Date(2026,9,12,9,51).getTime();await core.setCampusOption('live',true);assert.equal(f.state.liveStarts.length,1);
 f.state.stopFail=true;f.state.writeFail=true;await assert.rejects(core.clearCampusCompanion());assert.equal(f.state.reminders.size,0);assert.equal(f.values.get('courseReminderEnabled'),false);assert.equal(f.values.get('liveViewEnabled'),false);
 f.state.stopFail=false;f.state.writeFail=false;await core.clearCampusCompanion();assert.equal(f.disks.get('/data/campus_widget.json'),'null');assert.equal(f.state.liveStops.length,2);
});
 test('live view state changes reach the device log',async()=>{
  // 实况窗成败只能看系统侧反应，真机验收靠这条日志判断走到哪一步，
  // 所以状态变更必须真的落一条 hilog，而不是只存在内存里。
  const f=fixture();f.state.now=new Date(2026,9,12,9,51).getTime();
  const core=await readyCourse(f);await core.setCampusOption('live',true);
  const entries=f.state.logs.filter(entry=>entry[0]==='info'&&String(entry[2]).includes('LiveView'));
  assert.ok(entries.length>0,'live view state change must be logged');
  const payload=entries.map(entry=>String(entry[3])).join(' ');
  assert.match(payload,/api=|status=/, 'the log must carry the api level and the state text');
 });
 test('disabled live view switch never starts a surface',async()=>{
  const f=fixture();f.state.liveAllowed=false;f.state.now=new Date(2026,9,12,9,51).getTime();
  const core=await readyCourse(f);await assert.rejects(core.setCampusOption('live',true));
  assert.equal(f.state.liveStarts.length,0);
  const logged=f.state.logs.filter(entry=>String(entry[2]).includes('LiveView'));
  assert.ok(logged.length>0,'the refusal reason must be logged as well');
 });
test('failed LiveView stop reports logout failure after privacy and reminder cleanup',async()=>{
 test('api level normalises the eight-digit encoding instead of trusting it raw',async()=>{
 test('reminder group names come from one constant, never a fresh literal',()=>{
 test('course reminders are cancelled by group, never by a stored id list',()=>{
  // reminderIds 曾经每登记一条就写盘 flush 一次（最多 24 次），但从没被读过：
  // 取消一律按 groupId 枚举。留着实属只写不读的死数据，回归钉住它不再出现。
  const source=fs.readFileSync(path.join(root,'entry/src/main/ets/services/CampusCompanionService.ets'),'utf8');
  assert.doesNotMatch(source,/reminderIds/);
  assert.match(source,/cancelReminderGroup\(COURSE_REMINDER_GROUP\)/);
 });
  // 注册与取消各写字面量时，拼写差一个字符就一条都取消不掉，系统提醒会在
  // 退出登录后继续弹给下一个账号。断言两侧都引用同一常量。
  const groups=fs.readFileSync(path.join(root,'entry/src/main/ets/services/ReminderGroups.ets'),'utf8');
  assert.match(groups,/export const COURSE_REMINDER_GROUP: string = 'campus_courses'/);
  assert.match(groups,/export const TODO_REMINDER_GROUP: string = 'campus_todos'/);
  for(const file of ['TodoReminderService.ets','CampusCompanionService.ets']){
   const source=fs.readFileSync(path.join(root,'entry/src/main/ets/services/'+file),'utf8');
   assert.doesNotMatch(source,/'campus_(?:todos|courses)'/,'no reminder literal may survive outside ReminderGroups');
  }
 });
  // 6.1.0(23) 的编码形态是 60100023。若门槛写成 1e8，这个值会原样参与比较，
  // 六千万对任何 api >= N 都成立，低版本设备就会拿到高版本字段。
  for (const [raw, expected] of [[60100023, 23], [60260000, 0], [26, 26], [19, 19], [0, 0], [-1, 0]]) {
   const f=fixture();f.state.sdkApiVersion=raw;f.state.now=new Date(2026,9,12,9,51).getTime();
   const core=await readyCourse(f);await core.setCampusOption('live',true);
   const view=f.state.liveStarts[0];
   if (expected >= 20) { assert.ok(view.liveViewData.capsule.tailIcon,'API ' + expected + ' must carry the tail affordances'); }
   else if (expected >= 12) { assert.ok(view.timer,'API ' + expected + ' must set the timer'); assert.equal(view.liveViewData.capsule.tailIcon,undefined); }
   else { assert.equal(view.timer,undefined,'API ' + expected + ' must not set the timer'); }
  }
 });
 const f=fixture();const core=await readyCourse(f);await core.setCampusOption('reminders',true);f.state.now=new Date(2026,9,12,9,51).getTime();await core.setCampusOption('live',true);assert.equal(f.state.liveStarts.length,1);
 f.state.stopFail=true;await assert.rejects(core.clearCampusCompanion());assert.equal(f.state.reminders.size,0);assert.equal(f.disks.get('/data/campus_widget.json'),'null');
 f.state.stopFail=false;await core.clearCampusCompanion();assert.equal(f.state.liveStops.length,2);
});
(async()=>{
 const results=[];for(const {name,run} of cases){try{await run();results.push({name,ok:true});console.log('PASS '+name);}catch(error){results.push({name,ok:false,error:error.message});console.error('FAIL '+name+'\n'+error.stack);}}
 const failed=results.filter(r=>!r.ok);const report={checkedAt:new Date().toISOString(),networkUsed:false,nativeApisMocked:true,checks:results.length,failed:failed.length,results};
 // 快照被跟踪，结论没变就别换时间戳，否则每次跑测试都把工作区弄脏。
 const snapshotPath=path.join(root,'.wolf/campus-companion-checks.json');
 const previous=(()=>{try{return JSON.parse(fs.readFileSync(snapshotPath,'utf8'));}catch(_error){return null;}})();
 const sameResult=previous!==null&&previous.checks===report.checks&&previous.failed===report.failed&&JSON.stringify(previous.results)===JSON.stringify(report.results);
 if(sameResult)report.checkedAt=previous.checkedAt;
 fs.writeFileSync(snapshotPath,JSON.stringify(report,null,2)+'\n');console.log(`${results.length} checks, ${failed.length} failed`);if(failed.length)process.exitCode=1;
})();
