# Android → iOS 迁移长期路线图

> 本文件是 iOS 迁移任务的唯一进度源。每完成一个可独立验收的功能切片，必须在同一次改动中更新状态、验证证据、关联提交和变更日志。

## 当前摘要

| 项目 | 当前值 |
| --- | --- |
| 总体状态 | 实现中 |
| 当前里程碑 | P0/P1：工程基线与 App Shell |
| 当前焦点 | SwiftUI 四入口与统一页面状态已实现；macOS CI 与手动未签名 IPA 构建已配置，等待首次运行验证 |
| 下一步 | 运行 macOS CI 和未签名 IPA workflow，在 iPhone 13 Pro 上用 Personal Team 完成首次 7 天签名安装；随后建立 Networking/Auth/Persistence 协议边界和 User/Course 模型 |
| 用户/平台功能进度 | 0 / 23 个切片已完成 |
| 当前分支 | `codex/feat/android-parity-migration` |
| 最近更新 | 2026-07-14 |

## 1. 目标与边界

### 1.1 长期目标

在 iOS 上以 Swift 和 SwiftUI 重建 AHUTong 的核心体验，使登录、课表、首页、学业查询、校园服务及系统集成达到可验证的 Android 行为对齐，同时遵循 iOS 的交互、安全、隐私和发布规则。

迁移以“行为与数据契约对齐”为准，不逐行翻译 Kotlin，也不按 Android 截图逐像素复刻。Android 中已知的安全问题、无效设置、提前提示成功等缺陷不得复制到 iOS。

### 1.2 当前范围

- 应用启动、协议确认、登录、会话恢复与退出。
- 四个主入口：主页、课表、小工具、设置。
- 课表、成绩、考试、空闲教室、校历和电话本。
- 校园卡余额与付款码、校园卡充值、浴室缴费、电控缴费。
- 天气、失物招领、学习资料。
- 首页自定义、课表桌面组件、课程提醒与可选 Live Activity。
- 测试、CI、辅助功能、隐私、安全与 App Store 发布准备。

### 1.3 明确不直接迁移

- Android APK 自更新、镜像下载、自安装、未知来源安装权限和动态 `.so` 更新。
- Android `BootReceiver`、精确闹钟、Glance Widget、Material/Compose 特效的原实现。
- Android 调试日志、硬编码客户端凭据、明文密码缓存和全局明文网络放行。
- Android 中失效或遗留的首登路由，不在确认产品行为前照搬。

iOS 对应能力分别使用 App Store/TestFlight、UserNotifications/BackgroundTasks、WidgetKit、SwiftUI 原生材质与系统交互重新设计。

## 2. 固定基线

| 仓库 | 基线 | 说明 |
| --- | --- | --- |
| AIO | `031ed3c2c599240a62184d928c3bcfbb22866607` | 迁移 worktree 的 detached HEAD |
| Android | `2a30a54e74127ce1b4f75763596b470bd0b9d01b` | 本路线图的功能与代码参考基线 |
| iOS | `96d33412ae47471d209b2e21c7b9715fc278d4f9` | 迁移开始前的 `main`；仅含两行 README |
| Android `sdk` gitlink | `8c2d6b8113cb0f2ea6bb45cd74fa950e39dc956d` | 尚未初始化；进入 Rust 可行性任务时再按需浅拉 |
| Android `GuiXu-Rust` gitlink | `2481ab378395b5ee6db21021524ad051d98b888f` | 尚未初始化；进入 Rust 可行性任务时再按需浅拉 |

基线不得静默替换。Android 参考版本变化时，必须在这里追加新 SHA，并在变更日志说明重新对照了哪些功能与契约。

当前 iOS 仓库没有 Xcode 工程、Swift 源码、测试、资源、CI、`.gitignore`、`LICENSE`、`AGENTS.md` 或项目本地 Skill。当前开发环境为 Windows，不能运行 `xcodebuild`；最终构建、Simulator、真机与 Archive 验证必须由 macOS/Xcode 或 macOS CI 完成。

## 3. 状态与更新规则

### 3.1 固定状态

| 状态 | 含义 |
| --- | --- |
| 未开始 | 尚未进入该切片 |
| 调研中 | 正在确认 Android 行为、API、平台差异或技术方案 |
| 实现中 | 已开始 iOS 代码实现，尚未达到验收标准 |
| 待验证 | 功能代码已完成，仍缺 macOS、Simulator、真机或真实环境验证 |
| 已完成 | 行为、构建/测试和证据均满足完成定义 |
| 阻塞 | 存在明确外部依赖，且已记录解除条件 |
| 暂缓 | 经确认当前版本不做，但仍保留在长期范围内 |

### 3.2 每个切片的完成定义

只有同时满足以下条件，功能才能标记为“已完成”：

1. Android 参考行为和 iOS 平台差异已经记录，未照搬已知缺陷。
2. 正常、加载、空数据、网络错误及相关登录失效状态均有明确表现。
3. 数据模型、解析、状态机或关键业务逻辑至少有对应单元测试或契约测试。
4. iOS 工程在指定 macOS/Xcode 基线上构建成功，相关测试通过。
5. 需要系统能力的功能已在 Simulator 或真机完成相应验证；支付必须使用受控测试账号或经授权的真实环境验证。
6. 不包含密码、Token、Cookie、支付签名、账号、签名证书或其他敏感信息。
7. 本表已写入验证命令/证据、Commit/PR、最近更新时间，且变更日志已追加记录。

只有 UI、Mock、占位文件或未经构建的代码不能标记为“已完成”，最多标记为“实现中”或“待验证”。

### 3.3 每次完成功能后的必更项

- 更新“当前摘要”中的状态、焦点、下一步、完成数和日期。
- 更新对应功能行的状态、验证证据、Commit/PR、日期和阻塞信息。
- 如发生行为取舍，在“平台差异与已知 Android 缺口”中记录决策。
- 如引入或解除风险，在“风险与阻断项”中同步更新。
- 在文件末尾的“变更日志”追加一行，不集中补记。

## 4. Android 现状结论

### 4.1 架构与数据链路

- Android 是单模块 `:app`，采用 Kotlin/Java、Jetpack Compose、Navigation 和 MVVM-ish 结构。
- 典型链路为 Screen → ViewModel → 全局 `AHURepository` → `BaseDataSource`，但天气、资源库和部分支付逻辑会绕过 Repository。
- 登录、课表、成绩、考试、余额等能力存在三级降级：Rust 本地 HTTP 服务 → Rust JNI → Kotlin `CrawlerDataSource`。
- 失物招领、校园卡支付等仍直接使用 Kotlin Retrofit/OkHttp；缓存主要使用 MMKV、DataStore、PersistentCookieJar 和 Rust KV。
- Android 核心业务几乎没有自动化测试，现有测试主要覆盖 APK 更新、分段下载和灰度策略。

关键入口：

- `app/src/main/java/com/ahu/ahutong/MainActivity.kt`
- `app/src/main/java/com/ahu/ahutong/ui/screen/Main.kt`
- `app/src/main/java/com/ahu/ahutong/data/AHURepository.kt`
- `app/src/main/java/com/ahu/ahutong/data/base/BaseDataSource.kt`
- `app/src/main/java/com/ahu/ahutong/data/crawler/SdkDataSource.kt`
- `app/src/main/java/com/ahu/ahutong/data/crawler/CrawlerDataSource.kt`
- `app/src/main/java/com/ahu/ahutong/sdk/RustSDK.kt`
- `app/src/main/java/com/ahu/ahutong/sdk/LocalServiceClient.kt`

### 4.2 迁移依赖链

```text
安全存储 / 网络会话 / Rust 能力审计
  → 登录与会话恢复
  → User/Course 模型、周次与课表缓存
  → App Shell、课表和首页
  → 学业工具与低风险校园服务
  → ycard 鉴权与支付安全门槛
  → 三类支付与写操作
  → WidgetKit、课程提醒和 Live Activity
  → 发布、隐私与质量验收
```

## 5. iOS 目标架构

初期采用单 App Target、单元测试 Target、UI 测试 Target，以垂直功能切片推进；在出现明确复用边界前不预先拆分多个 Swift Package。

```text
iOS/
├── AGENTS.md
├── .gitignore
├── README.md
├── project.yml
├── docs/migration/android-parity.md
├── AHUTong.xcodeproj/  # 由 XcodeGen 生成，不进入版本控制
├── AHUTong/
│   ├── App/
│   ├── Core/
│   │   ├── Auth/
│   │   ├── DesignSystem/
│   │   ├── Networking/
│   │   ├── Persistence/
│   │   └── Models/
│   ├── Features/
│   └── Resources/
├── AHUTongTests/
└── AHUTongUITests/
```

| Android 能力 | iOS 目标 |
| --- | --- |
| Compose `NavHost` / 底栏 | SwiftUI `NavigationStack` + `TabView` |
| ViewModel + StateFlow | `@MainActor` 状态模型；基线允许时使用 Observation，否则使用 `ObservableObject` |
| Retrofit / OkHttp / Gson | `URLSession`、`Codable`、结构化错误与可注入 Transport |
| OkHttp Authenticator / 全局锁 | `AuthSession` actor，统一 Cookie/Token 刷新和并发去重 |
| MMKV / DataStore | 普通偏好使用 `UserDefaults`，结构缓存使用文件或 SwiftData |
| 密码 / Token / Cookie | Keychain，必要时使用 ThisDeviceOnly 访问级别，并按用户隔离 |
| Hilt / object 单例 | 协议驱动的显式依赖注入；App 根部组装依赖 |
| Jsoup | 经评估后使用 Swift HTML 解析库，或复用 Rust 解析能力 |
| Glance Widget | WidgetKit，共享只读课表快照 |
| AlarmManager / BootReceiver | UserNotifications / BackgroundTasks，并接受系统调度限制 |
| Android 岛卡实验 | 独立评估 ActivityKit Live Activity，不与基础提醒绑定完成 |
| 文件打开 / 保存相册 | Quick Look、Share Sheet、PhotoKit 权限与降级路径 |
| APK 更新 | 不迁移；使用 App Store / TestFlight |

## 6. 关键决策

| ID | 决策 | 当前状态 | 影响 / 解除条件 |
| --- | --- | --- | --- |
| D-001 | Bundle ID、Display Name、最低 iOS、Xcode/Swift 基线、签名团队 | 临时基线已记录 | 当前使用 `com.openahu.ahutong`、安大通、iOS 17、Xcode 26、Swift 6；签名团队和最终参数仍须在合并/发布前固定 |
| D-002 | iOS 子仓许可证是否与 AIO 的 GPL-3.0 一致 | 待确认 | 发布前必须有明确许可证与第三方声明 |
| D-003 | Rust crate 是否支持 Apple target、staticlib/XCFramework 及 C ABI/UniFFI | 待调研 | P0 按需浅拉 `sdk`、`GuiXu-Rust` 后做 spike；不得预设可直接复用 |
| D-004 | Rust 直连 FFI、本地 loopback HTTP 或 Swift `URLSession` 的主数据方案 | 待调研 | 首选直接 FFI；loopback 服务需额外评估生命周期与审核风险 |
| D-005 | 支付签名与客户端凭据的服务端化、轮换方案 | 阻塞支付 | 完成安全整改前禁止进入支付上线验收 |
| D-006 | macOS CI、Simulator 设备矩阵与真机验证负责人 | CI 与未签名 IPA workflow 已配置，待首跑 | `.github/workflows/ios-ci.yml` 使用 macOS 26 动态选择可用 iOS Simulator；`.github/workflows/ios-unsigned-ipa.yml` 在 `codex/**` 推送时运行并支持默认分支手动触发；真机验证由用户在 iPhone 13 Pro 上执行 |
| D-008 | 当前无付费 Apple Developer Program 账号时的真机分发方式 | 已确定开发期方案 | GitHub Actions 只生成未签名 IPA；Apple ID 不进入仓库或 GitHub Secrets；本机使用 Personal Team/Sideloadly 或 AltStore 签名，每 7 天刷新；该方式不等同于 TestFlight/App Store 发布 |
| D-007 | 崩溃上报、灰度、统计与广告方案 | 待确认 | 必须先完成隐私清单、数据用途和 App Store 合规评估 |

## 7. 里程碑

| 阶段 | 目标 | 出口条件 | 状态 |
| --- | --- | --- | --- |
| P0 | 契约、安全与工程基线 | 完成关键决策；建立 DTO/golden fixtures；Rust/Swift 数据方案有结论；无敏感信息入库 | 调研中 |
| P1 | App 骨架与离线样例 | SwiftUI 四入口、主题、导航、依赖注入、Mock、单测/UI smoke 可在 macOS CI 运行 | 实现中 |
| P2 | 核心闭环 | 登录/退出/恢复会话、课表、首页今日课程、离线缓存、多账号隔离完整 | 未开始 |
| P3 | 教务域 | 成绩/GPA、考试、空闲教室契约与 UI 完整 | 未开始 |
| P4 | 低风险校园服务 | 余额/二维码、失物只读、校历、天气、电话本、学习资料完整 | 未开始 |
| P5 | 写操作与支付 | 失物发布/删除和三类支付通过安全、幂等、失败恢复及真机验证 | 未开始 |
| P6 | 平台增强 | WidgetKit、课程提醒、可选 Live Activity、后台刷新与辅助功能完整 | 未开始 |
| P7 | 发布 | Release Archive、签名、权限文案、隐私清单、TestFlight/App Store 清单完整 | 未开始 |

## 8. 功能迁移矩阵

说明：Android 路径均相对于 Android 子仓根目录；iOS 目标路径会随工程骨架创建。`—` 表示尚无验证或提交证据。

| ID | 功能切片 | Android 参考 | iOS 目标 | 优先级 / 依赖 | 状态 | 核心验收 | 验证 / Commit | 更新 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| APP-01 | App Shell、四入口与统一状态 | `ui/screen/Main.kt`、`BottomNavBar.kt` | `App/`、`Core/DesignSystem/` | P1 | 待验证 | 已实现主页/课表/小工具/设置顺序、`NavigationStack`/`TabView`、统一 idle/loading/loaded/empty/failed 状态和 Dynamic Type 友好占位页 | Windows：YAML/JSON 解析、14 个 Swift 文件分隔符、空白检查通过；2 组单元测试和 1 条 UI smoke 已写，待 macOS CI；Commit — | 2026-07-14 |
| AUTH-01 | 启动、三份协议与首登流程 | `ui/screen/Splash.kt`、`ui/screen/setup/*` | `Features/Onboarding/` | P1 / APP-01 | 未开始 | 协议可读、同意状态持久化；拒绝与再次查看路径明确；不复制遗留 `Setup` 路由 | — | 2026-07-14 |
| AUTH-02 | 登录、会话恢复、过期重登与退出 | `Login.kt`、`LoginViewModel.kt`、`AHURepository.kt`、`crawler/manager/*`、`sdk/*` | `Core/Auth/`、`Features/Login/` | P2 / D-003~D-005 | 未开始 | 首次登录、冷启动恢复、并发刷新去重、过期重登、退出清理、多账号隔离；密码/Token/Cookie 仅进 Keychain | — | 2026-07-14 |
| SCH-01 | Course 模型、周次解析、API 与离线缓存 | `data/model/Course.java`、`CurrentWeekResolver.kt`、`SdkDataSource.kt`、`AHUCache.kt` | `Core/Models/`、`Features/Schedule/Data/` | P2 / AUTH-02 | 未开始 | golden fixture 可解析；单双周/跨学期/当前周测试；缓存按用户隔离；无网可读 | — | 2026-07-14 |
| SCH-02 | 课表 UI、课程详情与设置 | `main/Schedule.kt`、`ScheduleViewModel.kt`、`main/schedule/*` | `Features/Schedule/` | P2 / SCH-01 | 未开始 | 20 周切换、日期、单双周、刷新、总览、课程详情、显示全部课程、下学期预览对齐 | — | 2026-07-14 |
| HOME-01 | 首页概览与 8 槽位自定义 | `main/Home.kt`、`main/home/*`、`DiscoveryViewModel.kt`、`data/gray/*` | `Features/Home/` | P2 / APP-01、SCH-01 | 未开始 | 今日课程、天气、余额/付款码入口、快捷工具槽位和编辑状态可用；灰度状态可注入 | — | 2026-07-14 |
| ACA-01 | 成绩、多学籍、GPA 与专业排名 | `main/Grade.kt`、`GradeViewModel.kt`、`data/model/Grade*` | `Features/Grades/` | P3 / AUTH-02 | 未开始 | 多学籍/微专业、学期筛选、搜索、绩点和排名契约对齐；解析有 fixture 测试 | — | 2026-07-14 |
| ACA-02 | 考试查询 | `main/Exam.kt`、`ExamViewModel.kt`、`data/model/Exam.java` | `Features/Exams/` | P3 / AUTH-02 | 未开始 | 缓存、刷新、搜索、考试状态、时间、考场和座号展示完整 | — | 2026-07-14 |
| ACA-03 | 空闲教室 | `main/FreeClassroom*.kt`、`FreeClassroomViewModel.kt` | `Features/FreeClassroom/` | P3 / AUTH-02 | 未开始 | 校区、楼栋多选、节次、日期范围查询和空/错状态完整 | — | 2026-07-14 |
| CARD-01 | 校园卡余额与付款码 | `home/CampusCard.kt`、`AHURepository.kt`、`TokenManager.kt` | `Features/CampusCard/` | P4 / AUTH-02 | 未开始 | 余额刷新、二维码生命周期、凭据过期和截屏/录屏提示策略明确；不承诺完全禁止截图 | — | 2026-07-14 |
| PAY-01 | 校园卡充值 | `main/CardBalanceDeposit.kt`、`CardBalanceDepositViewModel.kt` | `Features/Payments/CardRecharge/` | P5 / CARD-01、D-005 | 未开始 | 金额校验、支付状态机、校内银行卡和支付宝跳转/降级、回到 App 后结果核验完整 | — | 2026-07-14 |
| PAY-02 | 浴室缴费 | `main/BathroomDeposit.kt`、`BathroomDepositViewModel.kt` | `Features/Payments/Bathroom/` | P5 / CARD-01、D-005 | 未开始 | 手机号查询、浴室选择、金额和六位支付密码流程完整；失败不提前提示成功 | — | 2026-07-14 |
| PAY-03 | 电控缴费 | `main/ElectricityDeposit.kt`、`ElectricityDepositViewModel.kt` | `Features/Payments/Electricity/` | P5 / CARD-01、D-005 | 未开始 | 校区→楼栋→楼层→房间、余额、历史选择、金额/密码、结果核验完整；无敏感请求日志 | — | 2026-07-14 |
| INFO-01 | 校历 | `main/SchoolCalendar.kt`、`sdk/RustSDK.kt` | `Features/SchoolCalendar/` | P4 | 未开始 | 下载、缓存、缩放、Quick Look/分享或保存相册及权限降级完整 | — | 2026-07-14 |
| INFO-02 | 电话本 | `main/PhoneBook.kt`、`TelDirectoryViewModel.kt`、`data/model/Tel.kt` | `Features/PhoneBook/` | P4 | 未开始 | 本地分类、搜索、校区号码和拨号确认完整；静态数据来源可追溯 | — | 2026-07-14 |
| INFO-03 | 天气 | `main/Weather.kt`、`WeatherViewModel.kt`、`data/weather/*` | `Features/Weather/` | P4 | 未开始 | GPS/IP/城市搜索、实况、预报、小时、AQI、生活指数和权限降级完整；设置项必须真实生效 | — | 2026-07-14 |
| CONTENT-01 | 失物招领只读 | `main/LostFound.kt`、`LostFoundViewModel.kt` | `Features/LostFound/` | P4 / AUTH-02 | 未开始 | 双列表、校区/类型/全文筛选、分页、详情与图片浏览完整 | — | 2026-07-14 |
| CONTENT-02 | 失物发布与删除 | 同上、`crawler/model/adwnh/*` | `Features/LostFound/Compose/` | P5 / CONTENT-01 | 未开始 | 仅在服务端确认后提示成功；“我的帖子”由可靠数据源生成；图片能力按已确认 API 范围实现 | — | 2026-07-14 |
| CONTENT-03 | 学习资料浏览与下载 | `main/Repository*.kt`、`RepositoryViewModel.kt`、`data/repository/*` | `Features/Repository/` | P4 | 未开始 | 仓库/目录浏览、缓存、进度、Quick Look/分享、单个和批量删除完整 | — | 2026-07-14 |
| PREF-01 | 设置、偏好、关于、许可证与贡献者 | `Settings.kt`、`settings/*`、`PreferencesViewModel.kt`、`LicenseViewModel.kt` | `Features/Settings/` | P1→P7 | 未开始 | 重登、清缓存、主题、首页/课表/提醒偏好均真实生效；第三方许可证清单完整可追溯 | — | 2026-07-14 |
| SYS-01 | WidgetKit 课表组件 | `appwidget/ScheduleAppWidget.kt`、`WidgetUpdateScheduler.kt` | Widget Extension | P6 / SCH-01 | 未开始 | 小/中/大尺寸按目标范围展示；共享快照、时间线、未登录/过期状态和点击跳转完整 | — | 2026-07-14 |
| SYS-02 | 课程提醒与可选 Live Activity | `notification/CourseReminder*`、`CourseLiveUpdateHelper.kt` | `Core/Notifications/`、ActivityKit Extension | P6 / SCH-01 | 未开始 | 通知授权、提前 10 分钟提醒、课表变化后重排、时区/重启场景完整；Live Activity 独立验收 | — | 2026-07-14 |
| OPS-01 | 灰度、诊断、隐私、CI 与发布 | `data/gray/*`、`settings/Debug.kt`、`.github/workflows/ci.yaml` | `Core/FeatureFlags/`、`.github/workflows/` | P0→P7 | 实现中 | macOS build/test、脱敏日志、崩溃/灰度策略、辅助功能、隐私清单、Archive 和发布清单完整 | 已配置模拟器 CI 和手动未签名设备 IPA workflow；Windows 静态检查待执行，macOS 构建及 iPhone 13 Pro 安装待验证；Commit — | 2026-07-14 |

## 9. 平台差异与已知 Android 缺口

| 项目 | Android 现状 | iOS 迁移决策 |
| --- | --- | --- |
| 首登流程 | `Setup.kt` 的登录路由已注释但仍导航，主登录当前直接进入 Home，`Info.kt` 非正常必经链路 | 先确认产品流程，再用单一状态机实现，不翻译遗留导航 |
| 密码与会话 | 密码、Rust Cookie、业务数据会进入 MMKV/Rust KV；Cookie 另有持久化副本 | 密码、Token、Cookie 使用 Keychain；普通偏好与结构缓存分离并按用户隔离 |
| Rust 复用 | Android 使用 `.so`、JNI 和本地 HTTP 服务 | 先验证 Apple targets 与 XCFramework；优先直接 FFI，不假定 loopback server 可照搬 |
| 会话续期 | 302 检测、全局状态、同步锁及本地密码重登 | 使用 `AuthSession` actor 统一刷新、并发去重、过期通知与显式重新认证 |
| 网络安全 | 存在全局明文流量配置 | 默认严格 ATS；仅对经论证的本地通信做最小例外 |
| 客户端凭据 | Android 支付链存在硬编码客户端凭据/签名材料及敏感日志 | 不记录具体值；先轮换并迁到服务端签名/安全配置，清理敏感日志，否则支付阻塞 |
| 课表 | 主要功能成熟；当前时间指示线有显式 TODO | 先完成行为对齐；时间线作为独立增强项，不阻塞首个课表切片 |
| 失物招领 | 图片上传未实现；发布/删除可能提前提示成功；“我的帖子”只过滤当前已加载数据 | 不复制缺陷；服务端确认后更新 UI，“我的帖子”使用可靠查询/分页语义 |
| 天气偏好 | 多个显示开关只改内存或未被首页读取，只有 `showOnHome` 持久化生效 | 只提供能真实生效并有测试的开关 |
| 许可证 | Android 列表标有 TODO，可能不完整 | 从 iOS 实际依赖生成/维护完整清单 |
| 浴室数据源 | `SdkDataSource.getBathRooms()` 当前为空响应，部分功能走其他直连接口 | 以实际接口契约和 fixture 为准，不复制空实现 |
| APK/热更新 | Android 有完整自更新、分段下载和安装流程 | 完全排除，走 App Store/TestFlight |
| 开发期真机安装 | Android 可直接安装调试 APK | 当前无付费 Apple Developer Program 账号；GitHub Actions 生成未签名 IPA，本机以 Personal Team 完成 7 天签名和刷新，不将 Apple ID、密码、证书或描述文件上传 GitHub |
| QQ/支付宝跳转 | 依赖 Android Intent/deep link | 使用 iOS URL Scheme/Universal Link 白名单，并提供未安装时降级路径 |
| 防截屏 | Android 登录/付款码可使用窗口安全标志 | iOS 只能做录屏检测、遮罩或风险提示，不承诺完全禁止截图 |

## 10. 安全门槛

以下条件在支付或真实账号广泛测试前必须完成：

- [ ] 确认并轮换 Android 中已暴露的客户端凭据和支付签名材料；iOS 仓库不得复制其值。
- [ ] 将签名或不可公开的业务能力迁到受控服务端，客户端只持有最小权限配置。
- [ ] 密码、Token、Cookie 全部进入 Keychain；缓存清理、退出登录和账号切换行为有测试。
- [ ] 建立脱敏日志策略，禁止输出 Cookie、Token、密码、完整请求体和可识别账号信息。
- [ ] `AuthSession` 统一处理 Cookie、Token、刷新、并发去重和过期事件。
- [ ] 默认启用 ATS，仅为必要域名或经论证的本地通信配置最小例外。
- [ ] 支付状态机覆盖重复提交、超时、取消、第三方 App 返回、服务端未知状态和结果对账。
- [ ] 真机测试使用经授权账号，并记录测试范围，不把测试数据或截图中的敏感信息入库。

## 11. 测试与验证策略

### P0/P1 起建立

- 为登录、课表、成绩、考试、空闲教室、校园卡和内容 API 建立脱敏 golden fixtures。
- 网络层通过可注入 Transport 支持确定性成功、空数据、错误、超时、401/302 和重试测试。
- 周次、单双周、跨学期、缓存命名空间、会话并发刷新、金额与支付状态机必须有单元测试。
- 每个主要导航路径至少有一条 UI smoke test。
- 所有用户可见页面检查 Dynamic Type、VoiceOver 标签、颜色对比度、深浅色和 Reduce Motion。

### 验证环境

| 环境 | 可验证内容 |
| --- | --- |
| 当前 Windows 工作区 | 文件结构、静态检查、fixture/纯逻辑（若工具链支持）、`git diff --check` |
| macOS CI / Xcode | 工程构建、单元测试、UI 测试、Simulator 截图、Release Archive |
| iOS 真机 | Keychain、定位、通知、WidgetKit、ActivityKit、相册/文件、第三方跳转、后台与支付 |

每次验证都在对应功能行记录实际命令、Xcode/iOS 版本、设备或 Simulator、结果和证据路径；不要只写“已测试”。

## 12. 风险与阻断项

| ID | 风险 | 等级 | 缓解与解除条件 | 状态 |
| --- | --- | --- | --- | --- |
| R-001 | Rust crate 的 Apple target、FFI 和依赖兼容性未知 | 高 | 按需浅拉嵌套子模块，完成 device/simulator 构建 spike 与接口样例 | 开放 |
| R-002 | 登录依赖多个校园系统、Cookie 同步、验证码/OCR 与页面解析 | 高 | 先固化脱敏 fixture/契约，建立统一 AuthSession 和可观测错误 | 开放 |
| R-003 | 客户端存在凭据、支付签名与敏感日志风险 | 严重 | 轮换、服务端化、日志审计完成前阻塞支付 | 阻塞支付 |
| R-004 | 支付缺少稳定沙箱，真实验证可能涉及资金 | 严重 | 授权测试账号、小额边界、幂等和结果对账方案齐备 | 阻塞支付 |
| R-005 | 当前 Windows 环境无法运行 Xcode | 高 | macOS 26 CI 已配置，待首次运行；真机验证流程仍需明确 | 缓解中 |
| R-006 | Android UI 截图较旧，不能作为唯一验收规格 | 中 | 以固定 SHA 的代码行为、API 契约和产品确认共同验收 | 开放 |
| R-007 | 核心 Android 业务缺少自动化测试 | 高 | iOS 迁移先补 fixture、解析、周次、会话和支付状态机测试 | 开放 |
| R-008 | 外部校园页面、第三方 API 与 App Store 政策可能变化 | 高 | 域隔离、契约监控、失败降级、隐私/审核复查 | 开放 |

## 13. 下一工作包

### P0-W1：工程与契约起点

- [x] 为 D-001 记录可替换的临时工程值。
- [ ] 确认 D-002 许可证、最终 Bundle ID 与签名团队。
- [x] 新增 iOS 子仓 `AGENTS.md`、`.gitignore` 和基础 README。
- [x] 创建 SwiftUI App、Unit Test、UI Test Targets 和四入口空壳。
- [ ] 建立 `Core/Networking`、`Core/Auth`、`Core/Persistence` 的协议边界与测试替身。
- [ ] 为 User、Course 和统一错误建立第一批模型与脱敏 fixtures。
- [x] 配置 macOS 26 CI，并动态选择可用 iOS Simulator。
- [x] 配置手动未签名 IPA workflow，供本机 Personal Team 7 天签名安装。
- [ ] 运行首次 macOS build/test，并把 Xcode、Simulator 与结果证据回写 APP-01。
- [ ] 运行首次未签名 IPA 构建，并在 iPhone 13 Pro 上完成安装/启动验证。

### P0-W2：Rust 与登录可行性 spike

- [ ] 按 AIO 规范仅初始化任务需要的 `sdk`、`GuiXu-Rust` 浅子模块。
- [ ] 验证 `aarch64-apple-ios` 与 Simulator target，尝试产出 staticlib/XCFramework。
- [ ] 对 login/schedule/cookies 做最小 FFI 样例，并与纯 Swift `URLSession` 方案比较。
- [ ] 形成 D-003、D-004 的明确结论；失败时保留 Swift 数据层回退路线。

## 14. 变更日志

| 日期 | 条目 | 变更 | 验证证据 | Commit / PR |
| --- | --- | --- | --- | --- |
| 2026-07-14 | INIT-001 | 建立 Android → iOS 长期路线图；固定三仓基线；完成 Android 功能、架构、安全风险和 iOS 空仓现状盘点；尚未迁移功能 | 只读源码审查；Android/iOS/AIO `git status` 均在改动前干净；未初始化 Android 嵌套子模块 | — |
| 2026-07-14 | APP-001 | 建立 XcodeGen 工程基线、SwiftUI 四入口、统一页面状态、单元/UI 测试骨架及 macOS CI；APP-01 进入待验证 | Windows：`project.yml`/workflow YAML 与 asset JSON 解析通过；14 个 Swift 文件分隔符和全仓空白检查通过；当前环境无 `xcodebuild`，未执行编译 | — |
| 2026-07-14 | OPS-001 | 新增 `codex/**` 推送及手动触发的 macOS 26 未签名设备 IPA workflow，产出 IPA 与 SHA-256 并保留 7 天；明确 Personal Team 本地签名边界 | Windows：PyYAML 6.0.3 解析成功，job/产物路径断言及 `git diff --check` 通过；当前环境无 `xcodebuild`，GitHub Actions 和 iPhone 13 Pro 安装待验证 | — |
