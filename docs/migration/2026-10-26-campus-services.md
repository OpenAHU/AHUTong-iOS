# 紧凑工具页、教务考勤、必吃榜与验证码续期（2026-10-26）

## 产品和源码边界

用户看过系统分组列表后要求双列卡片，随后提供 Android 参考图，确定四类标题 + 浅底细描边双列卡片。当前使用 `ScrollView`、分组 `VStack` 和双列 `LazyVGrid`，16 个 `NavigationLink` 不因固定到首页而消失；系统搜索、工具栏、TabView 与 Widget Form/sheet 保留。分类优先于将全部入口挤入一屏，大字号自然换行和滚动，不压缩用户字体。

卡片使用 18pt 连续圆角、系统自适应底色与 separator 描边，整卡可点，分类标题提供 VoiceOver heading。按压复用设置页的轻触觉、明暗反馈和 0.12 秒短缩放，抽为 `Core/DesignSystem/PressFeedbackStyle.swift`；开启减弱动态效果时禁用缩放及动画，保留高亮和触觉。详情页沿用系统 NavigationStack 转场。搜索只显示有结果的分组，不添加入场队列、延迟点击或持续装饰动画。

动效依据：Apple [Motion](https://developer.apple.com/design/human-interface-guidelines/motion) 建议反馈短而精准、尽量复用系统行为并支持减少动态效果；[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) 要求清晰按压态与足够触控范围。本页卡片最小高 54pt，布局由内容和 Dynamic Type 扩展。

Android 固定参考 `680abc29e2df7da0c2c650e2f88c8355327bc01d`（3.4.7-beta1）；读取 `KqcardAttendanceRepository.kt`、`AttendanceJsonParser.kt`、`CanteenApi.kt`、`CanteenRankingViewModel.kt`、`WisdomLoginFlow.kt`、`CrawlerLoginFlow.kt` 和对应 screen。未修改 Android、推送、合并或触发 Actions。

## 教务考勤

- 从 ADWMH `/commapp/myapp` 查找名称“教务考勤”或 ID 2035，解析 `lk/url/appUrl`；跟随受控学校 HTTPS 重定向及 200 页中的 `location.href` 字符串，不执行 JavaScript。
- 仅允许 one/adwmh/kqcard 三个明确学校域名和 HTTPS 默认端口，校方 http 入口升级 HTTPS，拒绝外域、凭据 URL 和任意端口。逐跳按 Cookie 域/路径发送，禁止自动跟随带凭据的重定向。
- 最终 kqcard 回调取 JWT，仅保留在该页面客户端内存，按 `exp` 和 60 秒余量复用。SSO Cookie 只在内存流转，不把 JWT 或 URL/query 写入日志/缓存。ADWMH JSON 失效走 campusCard 协调续期，CAS 失效走 academic；分页 HTTP 401 后仅换一次 JWT。
- POST `attendance-student/classWater/getClassWaterPage` 为只读查询，沿用 Android 的 `classWaterBean/status`、`current`、`pageSize=10`、`subjectBean/sCode`、`timeCondition` 和请求头契约。
- 原生状态分段选择器、分页、下拉/工具栏刷新、详情和加载/空/错误状态。缺勤日期优先取 `accountBean.checkdate/startJc/endJc`，不把 01-01 学期模板当真实上课日期。模型不包含抓拍照片，也不请求照片或提交申诉。
- 本轮协议与界面验收使用隔离 fixture；真实账号 SSO/记录尚待用户账号实机只读验收。

## 必吃榜

- 只读请求 Android 的 `https://inchangejiang.cn/api/canteen/insights`，参数 `period=week/month/all`、`limit=50`、`minTxns=20`，校区对应同一食堂集合。
- 使用独立 ephemeral URLSession，不附带学校 Cookie、学号、卡号、Authorization 或个人账单。当前不包含交易上传、窗口纠错/确认、远端匿名身份或写入密钥；食堂足迹与众包不是本轮交付范围。
- 近 7 天/近 30 天/全部、校区筛选、窗口排行与详情、平均每笔金额、样本范围与置信说明、食堂排行、用餐时段和每日趋势使用系统 List/Form/Picker/Swift Charts。推荐项无 rank 的真实响应单独兼容，避免整页解码失败；未命名窗口明确显示，不以终端编号虚构名称；样本热度不是口味评分。
- 每次新进入取新数据，页面内切换使用 5 分钟缓存，手动刷新绕过缓存；旧请求不覆盖新筛选，保留旧内容时仍标注旧数据的实际范围。
- 最初 `curl`/网页读取失败不能证明 App 网络失败。用户确认 Android 正常后继续核对：Apple URLSession 返回 HTTP 200，IPv6 curl 成功，而 IPv4/TLS 路径失败。最终将现有客户端及 Codable 模型以 -Osize 编译进临时验证程序，在指定 iPhone 17 Pro 模拟器运行时实际查询：week/all 50 条排名、11 个食堂、11 个小时分布；month/longhe 34 条排名、4 个食堂、10 个小时分布，推荐项均解码成功。见 `canteen-live-simulator.log`；没有修改地址、绕过证书或降低 TLS。此证据覆盖真实公开请求和解码；UI 截图仍为隔离演示内容。

## 登录 / OCR 修正

用户后续明确：2026-10-26 下午 OpenAHU 服务器曾短时故障，现已恢复，今天的 OCR 失败与该故障有关；本轮没有取得当时服务端日志，按用户现场反馈记录，不再将这次失败直接归因为 iOS 续期缺陷。用户已安排另一 agent 探索本地 Vision OCR，本轮只调整工具 UI，不修改识别器或对方工作区。此前源码对照确认 iOS 仅单次挑战、Android 最多 5 次，独立的 `CampusCardLoginFlow` 容错改动保留：

2026-10-27 用户确定暂时继续使用服务器。`CampusWebAuthentication` 和 `CampusCardLoginFlow` 默认均注入 `RemoteCampusCaptchaRecognizer`，使用 `https://openahu.org/ocr/captcha`；当前正式 App 源码没有接入 Vision 识别。仅发送验证码图片，不发送学校账号、密码或 Cookie。本地 Vision 探索不随本轮候选打包。

1. 每次获取新图片，合并并携带校方轮换 Cookie。
2. 只对 OCR 四位格式不符、校方明确验证码拒绝重新取图，最多 5 次；网络、超时、解析/服务端异常和明确账号密码拒绝立即停止。
3. 校方业务码 10012 优先分类为账号密码拒绝，即使文案包含“验证码”也不重试。
4. 保留四位字母数字校验，不放宽为任意 OCR 文本，不向识别服务发送账密/Cookie。
5. 校园卡隐藏登录总预算从 30 秒改为 90 秒，包含页面加载和最多 5 次挑战；教务保持 30 秒。取消任务会中断后续取图/提交。90 秒是全流程上限，并非每次重试都额外等待 90 秒。
6. OCR 失败仍只报校园卡续期失败，不清理已保存的教务账号和离线课表；沿用共享刷新协调，支付写请求不自动重放。

本轮定位和修复能覆盖这类瞬时挑战失败，不能据此宣称实机永不掉登录；需要真实设备再次复验首次打开、过期后校园码和快捷指令入口。

## 教务通知与 APNs 评估

当前只有课程本地提醒，没有 `aps-environment`、APNs 注册及公告订阅服务。教务通知列表、详情、缓存和未读可先独立实现；App 未运行时的新增公告提醒建议采用：公开公告抓取/去重 → 用户选择来源 → 自有通知服务 → APNs 可见通知 → 点击打开原文/详情。

APNs 不负责抓取学校网站。服务端需要凭据管理、device token 生命周期和失效清理；客户端需用户通知授权、现有 App ID 的推送 entitlement 及匹配签名描述文件。不需要另建 App ID；本轮未创建资源或添加后台假任务。

静默推送和 BGAppRefresh 受系统调度、节流、强制退出等限制，不保证准点或持续运行；APNs 可见通知也不保证必达。公开公告订阅只需 device token 与来源选择，不应上传学校账号、密码或 Cookie；若将来上线，需同步说明该数据用途、撤回和服务端删除。

依据：[Apple：远程通知服务端](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)、[注册 APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)、[后台推送限制](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)。

## 验证证据

见长期路线图 E-20261026-02；新单元测试按独立协议/状态场景组织，Swift 总数仍为 500。所有模拟器验证只使用 iPhone 17 Pro / iOS 26.5。现场截图明确使用演示数据，不冒充真实成绩、考勤或榜单网络验收。
