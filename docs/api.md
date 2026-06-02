# XJIT API 接入文档

## 基础信息

```text
Base URL: http://103.236.73.149:8765
OpenAPI: /api/v1/openapi.json
Feature detail: /api/v1/features/detail
Business endpoint: POST /api/v1/run
```

接口标题：XJIT 平台统一接口  
接口版本：0.1.0  
确认日期：2026-06-03

## 健康检查

```http
GET /health
```

当前返回：

```json
{
  "ok": true
}
```

## 统一请求

所有业务功能通过 `POST /api/v1/run` 调用。

```json
{
  "username": "学号",
  "password": "CAS密码",
  "feature": "jw.profile",
  "params": {},
  "captcha": "可选验证码",
  "rememberMe": true
}
```

字段说明：

- `username`: CAS 学号/账号，必填
- `password`: CAS 密码，必填
- `feature`: 功能名，必填
- `params`: 功能参数，不同功能结构不同
- `captcha`: CAS 需要验证码时填写
- `rememberMe`: 是否提交 CAS rememberMe

## 统一响应

成功：

```json
{
  "ok": true,
  "data": {}
}
```

失败：

```json
{
  "ok": false,
  "error": "错误信息"
}
```

前端注意：`ok: true` 不一定代表业务数据有效，空账号调用部分功能时可能返回空对象。页面层要检查关键字段。

## Feature 列表

| Feature | 功能 | 参数 |
| --- | --- | --- |
| `jw.profile` | 教务个人信息 | 无 |
| `jw.schedule` | 课表 | `term?` |
| `jw.grades` | 成绩/学分绩点 | `term?`, `mode?` |
| `jw.exams` | 考试安排 | 无 |
| `jw.training` | 培养/毕业完成情况 | 无 |
| `newcard.balance` | 校园卡余额 | 无 |
| `newcard.transactions` | 校园卡流水 | `fromDate?`, `toDate?`, `tradeType?`, `pageNo?`, `pageSize?` |
| `newcard.electricity.account` | 宿舍电费/剩余电量 | `roomQuery?`, `raw?`, `location?` |

## 功能详情

### `jw.profile`

个人基础信息。

请求：

```json
{
  "username": "学号",
  "password": "CAS密码",
  "feature": "jw.profile",
  "params": {}
}
```

返回数据：

```json
{
  "studentId": "学号",
  "name": "姓名",
  "college": "学院",
  "major": "专业",
  "className": "班级",
  "grade": "年级",
  "gender": "性别"
}
```

有效性判断：`studentId` 或 `name` 至少一个非空。

### `jw.schedule`

当前或指定学期课表。

参数：

```json
{
  "term": "2025-2026-2"
}
```

`term` 不传时使用教务默认当前学期。

返回数据：

```json
{
  "term": "当前学期",
  "courses": [
    {
      "day": "星期一",
      "slot": "第一大节",
      "title": "课程名",
      "teacher": "教师",
      "weeks": "1-16周",
      "sections": "1-2节",
      "location": "教室"
    }
  ]
}
```

有效性判断：`courses` 是数组。

### `jw.grades`

成绩、学分和绩点汇总。

参数：

```json
{
  "term": "2025-2026-2",
  "mode": "best_by_course"
}
```

`mode` 可选：

- `best_by_course`: 默认，同一课程取绩点/分数最高的一条
- `raw`: 原始统计模式

返回数据包含：

- `summary`: 去重后的汇总
- `rawSummary`: 原始汇总
- `terms`: 学期汇总
- `normalGrades`: 正常成绩
- `makeupGrades`: 补考/重修成绩
- `failedCourses`: 未通过课程

有效性判断：`summary`、`normalGrades`、`makeupGrades`、`failedCourses` 至少一个存在。

### `jw.exams`

考试安排。

请求参数为空。

返回数据：

```json
{
  "exams": [
    {
      "courseName": "课程名称",
      "teacher": "教师",
      "examTime": "考试时间",
      "examPlace": "考试地点",
      "seatNo": "座位号",
      "courseCode": "课程编号",
      "examSession": "考试场次",
      "campus": "校区"
    }
  ]
}
```

有效性判断：`exams` 是数组。空数组是合法的无考试状态。

### `jw.training`

培养或毕业完成情况。

请求参数为空。

返回数据：

```json
{
  "training": [
    {
      "graduationYear": "毕业届别",
      "graduationType": "毕业类型",
      "graduationConclusion": "毕业结论",
      "graduationTime": "毕业时间",
      "certificateNo": "毕业证书编号"
    }
  ]
}
```

有效性判断：`training` 是数组。空数组是合法的无数据状态。

### `newcard.balance`

校园卡账户余额。

请求参数为空。

返回数据：

```json
{
  "accounts": [
    {
      "typeCode": "账户类型编号",
      "typeName": "账户名称",
      "balance": "余额",
      "unit": "元"
    }
  ]
}
```

有效性判断：`accounts` 是数组。

### `newcard.transactions`

校园卡交易流水。

参数：

```json
{
  "fromDate": "2026-05-01",
  "toDate": "2026-06-03",
  "tradeType": "1,2,3",
  "pageNo": 1,
  "pageSize": 20
}
```

默认：

- `fromDate`: 最近 30 天
- `toDate`: 今天
- `tradeType`: `1,2,3`
- `pageNo`: `1`
- `pageSize`: `20`

返回数据：

```json
{
  "fromDate": "2026-05-01",
  "toDate": "2026-06-02",
  "tradeType": "1,2,3",
  "transactions": [
    {
      "date": "交易时间",
      "summary": "摘要",
      "merchantName": "商户",
      "amount": "金额",
      "isRefund": "是否退款",
      "journo": "流水号"
    }
  ]
}
```

有效性判断：`transactions` 是数组。

### `newcard.electricity.account`

宿舍电费/剩余电量。

参数：

```json
{
  "roomQuery": "9#312"
}
```

`roomQuery` 支持宿舍号简写，例如：

- `5#524`
- `3#312`
- `9#312`
- `5号楼524`

返回数据：

```json
{
  "remainingElectricity": {
    "value": "28.15",
    "unit": "度"
  },
  "room": {
    "query": "9#312",
    "buildingName": "9号宿舍楼",
    "levelName": "3层",
    "roomName": "312房间"
  }
}
```

有效性判断：`remainingElectricity.value` 存在。

## Dart 枚举建议

```dart
enum XjitFeature {
  profile('jw.profile'),
  schedule('jw.schedule'),
  grades('jw.grades'),
  exams('jw.exams'),
  training('jw.training'),
  cardBalance('newcard.balance'),
  cardTransactions('newcard.transactions'),
  electricityAccount('newcard.electricity.account');

  const XjitFeature(this.value);
  final String value;
}
```

## 安全要求

- 不在日志输出 `username` 和 `password`。
- 不把 CAS 密码写入普通缓存。
- 请求失败时只展示必要错误信息，不展示完整原始响应。
- App 内明确标注民间版本，避免用户误认为官方应用。
