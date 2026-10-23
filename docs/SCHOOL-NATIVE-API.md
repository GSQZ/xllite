# 学校原生接口直连说明

> 本页保留 10 月 9–10 日的契约核对与实施记录。当前代码按会话来源选择学校直连或整条网关分支，并非逐功能原生优先后自动兜底；XLLite 在线可用性与完整链路尚待专项验收。

更新：2026-10-09。需求：直接接入新疆理工学院原生服务，不采用自建反向代理或原项目 IP 网关。
另：2026-10-10 新增 XLLite 统一网关（`https://xllite.sayqz.com`，参照 GSQZ/xllite 仓库）兜底通道，
覆盖 13 个 feature 的登录/刷新/退出与业务调用；学校原生直连仍优先，网关会话下未适配的 feature 自动重定向。

## 当前交付范围

应用业务请求已迁移到学校 HTTPS 域名。个人信息、校园卡余额、消费流水三个原生适配器已实现；它们的请求和字段依据学校公开客户端代码，并通过模拟契约回归。模拟器已安装学校直连包，实际打开学校 CAS 登录页。

**尚未完成全部原生业务接入。** 未使用真实账号登录，三个适配器也未获得登录后的业务成功证明。另有十个业务标识缺完整、可验证的原生协议。目前提供的学校网页入口仅为临时访问方式，不计为原生接口完成。旧设计预览中的合成课程、余额和付款码不证明真实业务已接通。

## 学校服务地址

| 用途 | 当前地址 | 应用用途 |
| --- | --- | --- |
| 统一身份认证 | `https://cas.xjit.edu.cn/cas/login` | 学校官方页面处理账号、密码、验证码和多因素认证 |
| 掌上新理工 | `https://superapp.xjit.edu.cn` | CAS 回调与官方校园入口 |
| 个人中心 | `https://authx-service.xjit.edu.cn/personal` | 原生读取个人信息 |
| 门户服务 | `https://portal.xjit.edu.cn/portal-api` | 已发现日历路径，原生适配尚待验证 |
| 一卡通入口 | `https://newcard.xjit.edu.cn` | 学校一卡通认证和临时网页入口 |
| 一卡通接口 | `https://newcard.xjit.edu.cn/server` | 原生读取余额、交易流水 |

正式源码不再使用旧的 `http://103.236.73.149:8765`、统一 `/api/v1/run` 或旧网关登录接口。历史报告和旧模拟器工具中的网关描述是历史记录，不是当前应用配置。

## 已实现的原生请求契约

### 个人信息：jw.profile

- GET `/api/v1/personal/me/user`，基址为个人中心。
- 请求头：`X-Id-Token`；`X-Terminal-Info: h5`，大小写按公开客户端设置。
- 成功包：`{ code: 0, data: { attributes: ... } }`。
- 已核实映射：`attributes.accountId` → 校园账号，`userName` → 姓名，`organizationName` → 组织/学院显示值。专业、班级、年级、性别没有依据，保持空值。
- 证据：`.wolf/native-api-discovery/superapp-pages-tab-my-my.txt` 及格式化文本，获取信息和原文 SHA-256 位于 `superapp-my-contract.json`。

### 校园卡余额：newcard.balance

- POST `/user/info`，基址为一卡通接口，请求体 JSON `{}`。
- 请求头：`Authorization` 为一卡通自身 token 原值，公开客户端没有添加 Bearer 前缀。
- 成功包：`{ success: true, code, message, resultData }`；读取 `resultData.user.balance` 或 `user.accTypes[].balance`。
- `user.username` 是一卡通显示名；`user.idSerial` 是一卡通身份字段。未证实它们与门户 `accountId` 的对应关系，不默认两套认证属于同一个人。余额和流水页面明确显示当前一卡通账户。
- 列表渲染键由应用生成，不把生成值当成学校支付所需账户类型编码。
- 证据：`newcard-source.formatted.txt`、`newcard-pages_home-home.formatted.txt`。

### 消费流水：newcard.transactions

- POST `/bllt/queryCardSelfTradeList`，使用一卡通 token 和 JSON 请求体。
- 参数：`starttime`、`endtime` 为 YYYY-MM-DD；全部交易 `tradetype: "-1"`；`pageNumber` 从 **0** 开始；`pageSize: 20`。
- 应用页面从第 1 页计数，发送时转换为学校第 0 页；默认查询本月首日至今天，校验真实日期、顺序和页码。
- 读取 `resultData.rows`、`totalpage`；`txamt` 按整数分除以 100；`txdate`、`mername` 分别显示日期与商户。不推断未核实的退款标识或交易编号。
- 列表触底追加下一页，同一请求防重；翻页失败保留内容和待取页码；手动刷新回到第 1 页并替换数据。
- 证据：`newcard-pages_plugins-mybill-transaction-transaction.formatted.txt`。

学校一卡通客户端存在 SM4 加密响应包装，当前使用 Harmony cryptoFramework 的 SM4 ECB/PKCS7 解包。回归通过 Node 系统加密提供者模拟调用真实 CryptoUtil；**这不等于 Harmony 设备 SM4 验证已通过**。

## 尚待原生接入的业务

（以下业务已实现**网关兜底**：登录走 XLLite 统一网关 `https://xllite.sayqz.com`（参照 GSQZ/xllite 仓库 docs/api.md），
`/api/v1/run` 一次性传学号+CAS密码+feature，Bearer Token 认证；学校原生地址仍优先直连，
网关会话（`auth_source=xllite-gateway`）下未实现原生适配的 feature 自动重定向到网关。
网关当前 TCP 8765 端口不通、80/443 无服务，实际请求需待网关恢复后验证，代码已就绪。）

下表列的是**学校原生直连**还缺什么。"尚未实施"指原生协议未落地，不代表功能不可用——这些业务在网关会话下已能走 `/api/v1/run`，其中两个支付入口（`newcard.recharge.create_order`、`newcard.electricity.recharge.pay`）已在 `RechargePage` / `ElectricityPage` 中实现下单与 WebView 支付跳转，并由 `XlliteGateway` 校验响应必须带回 `payResult` 对象。

| 业务标识 | 已知线索与缺口 |
| --- | --- |
| jw.schedule | 学校日历有 getEvents/getSection/getWeekOfTeaching；教务课程另有 courseTable/day、courseList/list 等。需确认认证后的动态服务地址、学期/周次、课程结构，不能把日历事件全部当课程 |
| jw.grades | 缺成绩接口的准确基址、查询条件、认证和响应契约 |
| jw.exams | 缺考试接口的准确基址和响应契约 |
| jw.training | 缺培养方案准确接口和响应契约 |
| newcard.campus_code.qrcode | 已见学校付款码页面，缺签发、有效期与原生响应的完整契约 |
| newcard.recharge.config | 已见充值页面，学校账户类型和选项需完整验证 |
| newcard.recharge.create_order | 涉及 consume/transaction、auth/getEncrypt、SM2 加密及 recharge/pay，尚未实施 |
| newcard.electricity.account | 已见电费页面，需确认房间/账户查询契约 |
| newcard.electricity.recharge.config | 需确认实际电费配置结构 |
| newcard.electricity.recharge.pay | 涉及交易编号、加密及 utilities/pay，尚未实施 |

教务客户端的 `cache_courseUrl` 是动态值，公开代码不足以确定实际学校教务基址；`ENV_STUDY_CENTER_URL` 的模板占位符也不能作为请求地址。未实现的适配返回明确不可用结果，不猜地址发送请求；充值和电费付款未发送 HTTP。

**功能影响：原生课表、下一节课、依赖新课表数据的桌面组件和课前提醒，目前缺真实数据来源，不能声称这些业务功能已经恢复。** 相关页面可打开学校日历，但网页内容不会自动形成已验证的原生课程数据。

网页采用 school HTTPS 主页面导航限制，学校之外的支付服务跳转会被拦截，所以临时付款网页入口也不保证可以完成支付。

## 登录、会话与性能处理

- CAS 回调使用学校掌上新理工首页。学校掌上新理工是 history 路由；一卡通使用 hash 路由，后者入口保留 `/#/pages...`。
- 登录由私密模式 WebView 承载。应用固定脚本仅在精确学校服务源读取学校客户端存储的会话字段，不读取密码或任意 cookie；没有暴露任意 JS 到原生桥。
- 门户 token 必须有有效未来 JWT 过期时间，并先用个人信息请求确认再保存。保存失败不报告登录成功；密码不保存在应用偏好中。
- 一卡通会话独立校验 /user/info，只存内存；学校给出的秒数转换为毫秒，不猜门户 token 可用于一卡通。
- 旧网关会话迁移时清除旧认证、缓存及关联校园信息。退出清除私密 Web 存储和会话；异步版本校验防止迟到请求恢复旧登录。
- 原生只读请求继续复用缓存、并发合并和分批预加载；后台不启动第二批；一卡通未认证时不预加载卡数据。预加载并发上限 2。
- 缓存带门户账号、协议版本、一卡通进程随机命名空间和会话版本。应用重启不会把旧一卡通缓存当成新认证结果；独立卡会话切换时余额与流水清除旧内容，拒绝旧请求成功或异常结果。
- 学校会话检查仅在页面可见时运行，单次执行、回读来源校验、有限重试与手动重试。该 WebView 会话流程仍缺自动化和真实登录验收。

## 验证证据与交付包

2026-10-09 最终结果：

- 服务回归 39 项、页面行为回归 43 项、校园能力回归 29 项，共 **111 项，0 失败**。这些是实际源码转译配合模拟网络/系统的检查，不是在线业务成功率。
- 新增分页、失败重试、刷新替换、门户不变但一卡通会话更换的回归；后者先复现旧结果回写和错误消息污染，再修复并通过。
- 正式 API26 增量构建通过；模拟器 API26 clean 构建通过。正式构建记录 74 项 ArkTS 警告，主要为既有系统能力/异常处理及新增加密能力提示；无编译错误。设备加密能力仍未验证。
- 两份最终包的 130 项输入哈希与构建快照一致，交付复核无漂移；包哈希校验通过。共享 entry/build 会被其他会话覆盖，使用下面保留路径。
- 独立包 `com.xjit.app.schoolnative`，显示名“掌上新理工·学校直连”，在 `127.0.0.1:10077` 安装、启动通过；SDK 公开 OpenHarmony 测试证书签名和验签通过，不是发布签名。
- [原生登录入口截图](../.wolf/school-native-emulator/01-native-login.png) 与 [学校 CAS 实际加载截图](../.wolf/school-native-emulator/03-school-cas-ready.png) 已目视检查。第二张早期加载截图不作为最终页面就绪证据。
- 未输入真实账号/密码、未验证认证后业务数据、未执行付款。未实现 WebView 会话自动化，也未进行 Harmony 设备 SM4 已知答案测试。

| 产物 | 保留路径 | SHA-256 |
| --- | --- | --- |
| 正式工程包，未签名 | .wolf/school-native-production/entry-default-unsigned.hap | BB38AF35894830C436F8E35EF691773D500620580E9AA03A91C37ABA82A95E3F |
| 模拟器独立直连包，测试签名 | .wolf/school-native-emulator/entry-school-native-signed.hap | 6528FF36F46CBDEEEBCB22FC0194CD322D85B826CD959B90D838FA6607B53CD7 |

结构化验收记录与测试日志保留在本机工具链目录，不随仓库分发；公开协议原文与格式化文本同样只作本地文本检查，未执行获取的学校 JS。

复用现有 DevEco Studio 26.0.0.851、SDK 26.0.0.105/API26、Node 24.14.1、Hvigor 6.26.8、JBR、HDC 和 SDK 随附公开测试签名。没有新增 SDK、依赖、插件、下载工具或全局环境配置。一次性脚本以标准输入执行，没有临时可执行脚本残留；可复用构建与回归工具保留。

## 下一次真实接入验证

在模拟器「掌上新理工·学校直连」的学校认证页面手动登录，密码不写入日志或文档。先确认个人信息原生请求是否成功，再进入校园卡余额并通过学校一卡通页面认证，返回核对余额和流水。两套账户名称需分别确认。

课表、成绩等后续适配需要认证后学校实际下发的服务地址、请求参数和脱敏响应结构；仅保留协议必要信息，不把 token、密码和完整个人数据写进日志或规范。付款要等交易签发与加密协议验证完成后单独验收，不能以查询回归替代。
