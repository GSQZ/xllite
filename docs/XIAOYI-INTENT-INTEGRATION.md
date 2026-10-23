# 小艺原生意图接入：SDK证据与实施边界

2026-10-17；尚未注册、发布或在小艺真机入口验证。

## 已核实

本机SDK的@ohos.app.ability.InsightIntentDecorator.d.ts说明：应用可用装饰器将页面、函数、Ability执行器、卡片及实体声明为意图，提供给智能问答、搜索和推荐入口。

- InsightIntentPage：把页面作为意图入口，不等于后台创建任务。
- InsightIntentFunction与InsightIntentFunctionMethod：联合声明类与静态函数，供AI入口执行。
- InsightIntentEntry：关联InsightIntentEntryExecutor与Ability，支持执行模式。
- InsightIntentForm：描述卡片添加入口，不等于待办数据自动同步。
- 通用声明含intentName、domain、intentVersion、可选schema及parameters。标准schema需匹配实际标准清单；自定义意图也需满足声明的必填参数。
- 这些装饰器相关基础声明标为since20，最低API23未因使用基础意图机制自动失配；仍需实际编译与设备分发验证。部分其他字段为26新增，不能笼统认为整个模块全部字段兼容API23。
- HMS的@hms.ai.insightIntent提供shareIntent、deleteIntent、deleteEntity等分享/删除能力；这些接口本身不是嵌入小艺聊天面板或自然语言转时间API。

官方垂域说明链接来自SDK注释：
https://developer.huawei.com/consumer/cn/doc/service/intents-ai-distribution-characteristic-0000001901922213

该链接HTTP200，但文本抓取仅返回“文档中心”，未读到标准任务schema与准入/审核正文；不据此编造标准名或发布条件。

## 推荐链路

优先把“创建学习任务”做成应用意图入口：收到标题、绝对时间与调用标识 → 登录及参数校验 → 原生确认页面 → 保存任务 → 系统提醒登记 → 返回真实状态 → 刷新桌面卡片。

不在没有用户确认的情况下解释歧义时间，不将设备当前日期硬编码为示例日期。时间需包括时区或明确解释策略；过去时间、缺少标题、重复调用、登出和切换账号均有独立处理。提醒失败可保留任务但须明确状态，不能返回“已准时提醒”。

## 2026-10-17 页面入口契约复核

本机SDK实际声明已逐段读取，非根据示例推测：

- IntentDecoratorInfo第87、99、108、117行要求intentName、domain、intentVersion、displayName；schema为可选，不填schema也不代表domain可任意命名。
- domain第89—92行明确要求参考官方垂域取值范围；目前尚无已核实的任务垂域值，不使用猜测的education/office或自定义字符串填充。
- PageIntentDecoratorInfo第333、342行：uiAbility可选，pagePath必填且必须对应存在的页面；navigationId与navDestinationName可选。
- InsightIntentPage第366—378行：仅适用于struct页面，基础能力since20。
- 当前EntryAbility在启动时加载LoginPage，而待办页面本身尚无独立登录闸门。直接把TodoPage装饰为AI页面入口可能绕开原启动登录路径；挂接前必须验证意图页面加载顺序及账号检查，不能只验证编译。
- 外部检索未取得可复核的平台正文，返回结果与意图无关，未作为平台契约证据。

已具备的应用内部前置条件：dueAt结构化时间、原生时间选择、串行持久化、卡片刷新、显式提醒登记、完成删除实况窗清理及失败重试。仍未具备：意图专用输入确认与幂等处理、平台垂域/分发确认、直接页面账号闸门和真机小艺触发证据。

## 实施前仍需落实

1. 任务模型从dueText升级为可调度的结构化时间并做好旧数据迁移；现有TodoService不是现成的账号隔离提醒系统。
2. 取得可用任务标准意图schema或核实自定义意图的分发方式及真机支持。
3. 核实是否需平台配置、注册、审核及如何验收；当前不宣称本地声明即可被小艺自然语言发现。
4. 完成独立原生任务编辑、提醒登记及卡片数据链路，再挂意图入口，避免意图直接写入未初始化的全局存储。
5. 回归入参、幂等、账号隔离、延迟回调、提醒失败与用户取消；编译成功不等于小艺已接通。

## 当前未实现

未添加假小艺按钮、未调用第三方模型冒充小艺、未猜schema、未请求系统待办私有接口。用户确认的是原生接入方向，不是平台能力已验收。
