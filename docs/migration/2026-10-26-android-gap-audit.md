# Android 最新源码与 iOS 差距审计（2026-10-26）

## 范围和基线

Android 官方 `master` 与 `develop` 在本次 fetch 后均为 **`680abc29e2df7da0c2c650e2f88c8355327bc01d`**，版本 **3.4.7-beta1（304011）**。仅通过 `git show origin/master:<path>` 阅读该提交的路由、界面及真实数据实现，没有切换或修改 Android 工作区，没有在 Android 模拟器运行。下文路径相对 Android 子仓；`app/...` 简写对应 `app/src/main/java/com/ahu/ahutong/`，功能模块的省略部分对应各模块 `src/main/java/com/ahu/ahutong/` 包路径；完整源码可从 [固定提交](https://github.com/OpenAHU/AHUTong-Android/tree/680abc29e2df7da0c2c650e2f88c8355327bc01d) 追溯。

iOS 对照当前 `codex/ios-sentry-widget-diagnostics` 本地源码（HEAD `9ad60dd` 加尚未提交的维护改动），同时读取官方 `main` `9e8478a`、`develop` `f7a79e0`。不把“有路由/有模型”当作真实环境已验收，也不把历史 25/25 分母当成最新 Android 的全量完成度。本轮不推送、不合并、不触发 Actions、不改 AIO gitlink。

## 能力差距与建议顺序

| 能力 | Android 实际实现证据 | iOS 状态与下一切片 |
| --- | --- | --- |
| 自定义课程 | `data/schedule/.../CustomCourse.kt`、`feature/schedule/.../CustomCoursesScreen.kt`、`app/.../RepositoryCustomCourseStore.kt`；可增删改，按账号和学期隔离存储 | **缺少。P1**：先用原生 Form 编辑课程，与官方课程合并展示；同步首页、Widget、提醒、快捷指令，保证刷新不删除手动课程 |
| 校园通知 | `app/.../data/notice/*`、`CampusNoticeScreen.kt`；安徽大学、教务处、研究生院、学院等来源，来源筛选、未读、缓存、历史分页和本地提醒 | **缺少。P1**：先只读列表、原文及账号隔离缓存，再补未读和提醒。iOS 现有课程本地通知不能替代教务公告；后台时效需单独评估，不直接承诺 APNs |
| 教务考勤 | `app/.../data/attendance/KqcardAttendanceRepository.kt`、`AttendanceScreen.kt`；从智慧安大应用入口获取 kqcard 会话，分页查询，401 后更新会话 | **客户端已实现，真实账号待验**：状态筛选、分页、详情、受控 SSO 与一次 JWT 续期；临时 JWT 仅内存。见 [实现记录](2026-10-26-campus-services.md) |
| 电费预测和多房间预警 | `feature/recharge/`、`ElectricityAlertChecker.kt`、`ElectricityAlertViewModel.kt`；余量/历史预测、房间配置、每日请求预算、账号切换隔离 | **部分已有。P2**：已有余额/房间选择/缴费链路；缺剩余天数、多房间预警及完整近期房间体验。先验证只读用电数据和预测，不能以演示房间代表真实查询成功 |
| 高级消费统计 | `app/.../ui/screen/main/BillingStats.kt`；以凌晨 4 点划分消费日，月支出趋势、食堂排行、餐点分布、高消费日及明细 | **部分已有。P2**：iOS 有按自然日期汇总的每日/商户统计与图表，缺 Android 的消费日口径、餐点/食堂分类和高消费日分析；先固定统计口径及边界样本 |
| 食堂足迹、必吃榜和窗口纠错 | `CanteenFootprintScreen.kt`、`CanteenRankingScreen.kt`、`data/canteen/CanteenApi.kt`；HTTPS 排名/窗口映射、校区筛选、去标识交易上传、确认/纠错 | **部分已实现**：必吃榜周期/校区/排名/统计已接入；真实公开查询已通过。足迹、上传和纠错仍缺少，不默认上传个人交易 |
| 研究生教务 | `data/crawler/gmis/PostgraduateScheduleSource.kt`、`PostgraduateScheduleViewModel.kt`、`AcademicFeatureAccess`；独立 GMIS 会话、课表及本科专属能力分流 | **缺少。目标用户为研究生时升 P1，否则 P2**。现有本科成绩多学籍不等于研究生支持；先明确 GMIS 登录、课表、周次契约与可用功能 |
| 详细个人/学籍页 | `ProfileScreen.kt`、`ProfileViewModel.kt`；账号类型、年级、学院、专业、学籍等 | **部分已有。P2**：设置首页有真实账户信息，缺完整独立学籍页。保持账户登录入口在设置首页，用原生 List 展示新增只读信息 |
| 学习通日历与任务 | `feature/xuexiaotong/`、`data/chaoxing/`；独立会话、作业/截止时间、课程进度、自建日程、提醒 | **缺少。P2，单独立项**：先本地日程及只读同步，再任务提醒。Android 已改成主标签，iOS 四入口仍按用户确定的主页/课表/小工具/设置，不自动替换 |
| 菜鸟身份码 | `Main.kt` 的 `identity_code`：淘宝内页外跳，浏览器回退 | **缺少。P3**：可评估系统 openURL 入口；这是取件身份码，与校园付款码不同，不新建无内容中转页 |
| 网费首页入口 | `HomeWidgetRegistry.kt` 的 `network_recharge` | **部分已有。P2 小改**：网费充值已在小工具中，首页可配置工具尚未包含网费；不将其列成整个网费功能缺失 |
| 学习资料选源体验 | `feature/settings/.../RepositorySettings.kt`；多源检测/重测及直连回退 | **部分已有。P3**：iOS 已有资料浏览、下载、Git LFS 及四种加速选择；缺 Android 当前的测速展示及完整选源策略，按接口可靠性专项核对，不能算整个资料功能缺失 |
| 首页及扫码偏好 | `feature/settings/.../Preferences.kt` 的默认显示付款码、导航栏扫码入口 | **可选产品差异，P3**：iOS 当前用首页点按展开及 Siri/快捷指令打开；是否增加默认展开偏好需另行确定，保持已确认的四个原生标签 |
| 运行期插件和行为预测 | `.ahup` v3、运行时 ABI、`personalization/*` | **平台/产品差异**：Android 动态加载方式不直接移植。iOS 优先原生能力；预测涉及新的数据与隐私边界，需另行决定 |
| 教学评价 | Android 仍有 `evaluation` 路由和业务 | **既定排除**：iOS 已按用户要求删除，不自行恢复入口或提交能力 |

## 已有能力，不重复列为缺失

- 本科课表、周日开始展示、成绩/考试、空闲教室、校历、电话本。
- 校园邮箱的原生列表、阅读、写信/草稿/联系人/附件及官方页面回退；本轮不向真实收件人发信。
- 本科培养方案完成度、校园卡只读账单和基础日/月/商户统计。
- 校园卡余额/付款码、校园卡充值、招行页面、浴室、电控、网费；支付实机验收边界继续保留。
- 天气、失物招领、学习资料与下载、主题色、首页布局。
- iOS 的 Siri/App Intents、WidgetKit、课前 Live Activity 是原生系统集成；Widget 真机共享权限及 Siri 短语匹配尚有外部验收边界，不能只凭模拟器勾选完成。

## 同名功能的行为差距

Android 当前 `DiscoveryViewModel` 已区分实时余额和旧快照：手动刷新使用官网 queryCard，较旧的后台/首屏结果不会覆盖新值；二维码手动刷新可触发实时余额。iOS 现有学校直连、SDK 回退、一次会话恢复和前台刷新机制已有测试，但本轮没有把整个最新 Android 余额来源优先级重新移植，列为下一轮校园码/余额一致性专项。不能用“以前对齐过”宣称所有新变化已同步。

Android 小工具 `MoreWidgetsScreen` 已明确保留首页固定的工具，本轮 iOS 同步该行为；小工具分类沿用缴费充值、学业教务、校园生活、学习工具。用户本次要求原生 UI，用户否定 List 后，iOS 按用户后续参考图改用四分类标题、双列浅底描边卡片、共享按压反馈及 NavigationLink，保留 searchable、Toolbar 和 Widget Form，不新增 UI 框架或材质开关。

## 与问卷的关系

已确认 25 人参与：课表 22（88%）、校园码 20（80%）、成绩/考试 19（76%）、水电网费与教务通知各 15（60%）、“安大必…”7（28%，完整选项未确认）、邮箱及其他各 2（8%）。这是多选问卷。“安大必…”不擅自解释为必吃榜或学习通。

建议先完成现有校园码/共享签名的稳定性验收，再安排 **自定义课程、校园通知**，随后考勤、电费预警及高级账单/食堂只读分析。研究生支持是否提前取决于目标用户。后续已按用户指定顺序实现教务考勤和只读必吃榜，真实环境边界见 [实现记录](2026-10-26-campus-services.md)；其余差距仍为待办，不添加占位入口。
