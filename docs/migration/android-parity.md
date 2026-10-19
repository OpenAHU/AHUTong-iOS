# Android → iOS 迁移长期路线图

> 本文件是 iOS 迁移任务的唯一进度源。每完成一个可独立验收的功能切片，必须在同一次改动中更新状态、验证证据、关联提交和变更日志。

## 当前摘要

| 项目 | 当前值 |
| --- | --- |
| 总体状态 | 当前 iOS 范围为 25 个切片，教学评价已按产品决策整体移除；余下 25 / 25 个切片均有客户端实现，五个支付切片仍待物理 iPhone 授权账号验收 |
| 当前里程碑 | iOS 登录为官方可见 WebView 首登和前台隐藏 WebView 校园服务认证；隐私 v4 披露 ADWMH 首次及续期均远端 OCR，接受或拒绝隐私后仍可选择只含课表与设置的体验账户 |
| 当前焦点 | 1.0.2 后续维护：原生设置与校园码恢复；补充首页刷新、可配置深浅色课表 Widget、本科培养方案、校园卡账单/消费统计；贡献名单补齐 zirui.xu 及全部年级；Siri 语音匹配与重签配置面板仍有实机验收边界。证据见 E-20261019-07/08/09 |
| 下一步 | 在本轮包上用授权 iPhone 验证首次登录及隔天恢复、真实成绩/考试、缴费查询与小组件注册；当前本机仅有 iOS 26.5 Simulator，iOS 27 真机仍待复验 |
| 客户端实现覆盖 | 历史固定范围 25 / 25；本轮新增的培养方案、账单/统计独立列示，不将历史分母当作最新 Android 全量覆盖率 |
| Android 生产行为对齐 | 历史固定基线、既定 iOS 范围为 25 / 25；不代表当前 Android master 全量对齐。最新 `595e63c` 的新增业务差距见 §9.1，本分支已补培养方案与只读账单/基础统计 |
| 严格完成定义 | 14 / 25（56.0%）；原摘要 16 与矩阵实际 15 不一致，本轮校准并将用户报告不可用的 SYS-01 重新置为待真机验证；不以本轮 Mock 或未签名包增加严格完成数 |
| 当前分支 | `codex/ios-native-ui-campus-code`；起点为已集成 1.0.2 的官方 main `7897a54` |
| 最近更新 | 2026-10-19 |

## 1. 目标与边界

### 1.1 长期目标

在 iOS 上以 Swift 和 SwiftUI 重建 AHUTong 的核心体验，使登录、课表、首页、学业查询、校园服务及系统集成达到可验证的 Android 行为对齐，同时遵循 iOS 的交互、安全、隐私和发布规则。

迁移以固定 Android SHA 的代码与该版本实际渲染结果为唯一产品基准。业务实现不逐行翻译 Kotlin，但用户可见 UI 必须逐屏、逐状态对齐 Android；Android 中已知的安全问题、无效设置、提前提示成功等缺陷不得复制到 iOS。

### 1.2 当前范围

- 应用启动、协议确认、登录、会话恢复与退出。
- 四个主入口：主页、课表、小工具、设置。
- 课表、成绩、考试、空闲教室、校历和电话本；本科培养方案完成情况。
- 校园卡余额与付款码、只读账单及消费统计、校园卡充值、招商银行充值、浴室缴费、电控缴费和网费充值。
- 天气、失物招领、学习资料浏览/Markdown 阅读/下载管理。
- 首页自定义、课表桌面组件、课程提醒与可选 Live Activity。
- 测试、CI、辅助功能、隐私、安全与 App Store 发布准备。

### 1.3 明确不直接迁移

- Android APK 自更新、镜像下载、自安装、未知来源安装权限和动态 `.so` 更新。
- Android `BootReceiver`、精确闹钟、Glance Widget、Material/Compose 特效的原实现。
- Android 调试日志、用户凭据、明文密码缓存和全局明文网络放行。支付协议签名常量仅按 D-005 的明确产品决策在私有兼容层中使用，不复制 Android 的敏感调试输出。
- Android 中失效或遗留的首登路由，不在确认产品行为前照搬。
- 教学评价与一键教评不纳入当前 iOS 产品范围，不保留入口、提交能力、服务访问或本地预设。

iOS 对应能力分别使用 App Store/TestFlight、UserNotifications/BackgroundTasks、WidgetKit、SwiftUI 原生材质与系统交互重新设计。

### 1.4 UI 完全一致硬约束

1. 固定基线表中的 Android commit 及其 Compose 实际渲染结果是唯一视觉真源；不得以“更符合 iOS”“更简洁”或个人审美为由重新设计。
2. 页面信息架构、组件类型、内容顺序、中文文案、图标语义、颜色、字号/字重、圆角、阴影、间距、留白、对齐、卡片尺寸、列表密度、底栏和顶部栏必须与 Android 保持一致；第 8～11 条记录的用户显式覆盖除外。
3. 正常、加载、空数据、错误、弹窗、菜单、搜索、展开/收起、刷新和权限降级等可见状态都必须逐一对齐；不能只对齐首屏静态状态。
4. iOS 只允许保留系统强制差异：安全区、Home Indicator、系统权限弹窗、系统返回手势、拨号/分享/Quick Look 等系统控制器。差异必须限制在系统边界内，并记录在平台差异表中。
5. SwiftUI 可以使用等价实现，但不得用默认 `List`、`Form` 或系统导航样式替代 Android 已明确设计的自定义外观；需要时应以自定义组件复现 Compose 布局。四入口底栏按第 8 条使用系统 `TabView`，设置表单与课表弹层按第 11 条优先使用系统组件。
6. 每个页面完成前必须保存同一设备尺寸、同一数据状态的 Android 与 iOS 截图，检查关键几何尺寸与颜色；主要页面必须有 UI 测试覆盖可见文案、入口和交互状态。
7. 本约束追溯适用于此前已标记完成的 APP-01、AUTH-01、INFO-01、INFO-02、INFO-03、CONTENT-03；这些切片在 UI 复验通过前统一回到“实现中”。
8. 2026-07-16 用户进一步明确四入口必须使用 iOS 原生底部导航，而非仅在自绘容器上调用 Liquid Glass API。根容器必须使用系统 `TabView`/`UITabBar`，iOS 26+ 的 Liquid Glass、折射、触控、辅助功能和后续系统演进全部交给系统；禁止自绘 `HStack + Button` 冒充原生 Tab Bar。Liquid Glass 默认启用，设置页不得提供开关、关闭路径或单独说明入口。入口顺序、图标、中文文案和选中语义仍与 Android 一致。
9. 2026-09-23 用户要求彻底删除 iOS Debug 页面与 App 信息卡隐藏入口；设置首页使用真实 App 图标。2026-09-24 用户进一步明确账户信息与真实账号登录保留在设置首页，仅隐私选择及登录偏好进入偏好设置。
10. 设置域所有可点击行必须在跳转或执行前提供可感知的按压态；iOS 使用轻触觉、明暗高亮和短缩放补足交互反馈，开启“减弱动态效果”时禁用缩放但不得移除非动态反馈。静态布局仍以 Android 为准。
11. 2026-10-19 用户进一步要求更多 iOS 原生 UI，明确指出设置通知按钮卡顿、iOS 26+ 课表设置缺少玻璃材质。设置首页/偏好使用系统 `Form`、`NavigationLink` 和真实 `Toggle`；系统开关保留原生操作与反馈，导航/动作行继续保留轻触觉及按压反馈。课表设置采用系统半高 sheet 和工具栏，不用实色背景覆盖系统 Liquid Glass；不提供玻璃开关。此条覆盖对应页面的 Android 静态组件复刻限制。

## 2. 固定基线

| 仓库 | 基线 | 说明 |
| --- | --- | --- |
| iOS 本轮原生 UI / 校园码基线 | `7897a54e92a929814d9a74776eab8d423604a842` | 官方 main；1.0.2 集成后起点 |
| Android 本轮最新功能与校园码参考 | `595e63c4615ec6d7e9602cc613c03022048fd0a9` | 官方 master，2026-10-19 抓取；只读检查，未改 Android 和 AIO 主工作区 gitlink |
| AIO 2026-10-19 维护 | `59e9ed1` | `ios-roadmap-survey` detached worktree；本轮实际使用 |
| iOS 2026-10-19 上游 | `449300f` | 本轮审查时的官方 `main` |
| iOS 2026-10-19 维护起点 | `cc3dd5f` | PR #3 精确尖端；续期、UI 和 Widget 维护在此基础上进行 |
| AIO 历史支付 worktree | `af388304f325ebe0f77286192e08633027072e91` | 历史 `ios-payment-production-parity` detached worktree；本轮未使用 |
| iOS 本轮支付基线 | `458ed7f392963f6b7943e71655cbe1609854b363` | 从已推送 iOS 主线状态创建 `codex/feat/payment-production-parity` |
| Android 本轮支付参考 | `2c33b0bb923f197f1d209cb58589a6b5d052cd9f` | PAY-01、PAY-02、PAY-03、PAY-05 的唯一生产协议参考；未使用旧 worktree 的 Android `2a30a54` |
| Android 本轮导航图标参考 | `6164917dede45485ef67b7437d0bc3dee7644f53`（3.2.2） | 2026-10-19 按用户要求读取当前 AIO 固定版本的 `BottomNavBar.kt`；仅覆盖四个导航图标形状对照，其他功能的既有基线不变 |
| Android 本轮 Session 参考 | `2c33b0bb923f197f1d209cb58589a6b5d052cd9f` | `AutoLoginInterceptor` 登录重定向语义、`TokenAuthenticator` 全局 mutex 与一次重试的唯一参考 |
| iOS 本轮 Session 基线 | `d8be7da` | 从支付生产证据收口后的远端分支创建 `codex/fix/session-expiry-refresh` |
| AIO | `031ed3c2c599240a62184d928c3bcfbb22866607` | 迁移 worktree 的 detached HEAD |
| AIO 3.2.0 历史复审 worktree | `205a19916dcba5d30da5925ed46d8bf453689113` | 历史 `ios-final-completion-audit` 根仓基线；本轮未使用其中旧 Android 子模块 |
| Android 原始固定基线 | `2a30a54e74127ce1b4f75763596b470bd0b9d01b` | 2026-07-14～17 已完成切片及旧 UI 证据的产品参考 |
| Android 3.2.0 复审基线 | `2c33b0b` | 2026-07-26 重新全量审计；新增教学评价、招商银行充值、网费充值，并扩展考试、资料库、首页、天气、设置等行为 |
| iOS | `96d33412ae47471d209b2e21c7b9715fc278d4f9` | 迁移开始前的 `main`；仅含两行 README |
| Android `sdk` gitlink | `8c2d6b8113cb0f2ea6bb45cd74fa950e39dc956d` | 已按需浅拉，并固定为 iOS `Vendor/sdk` 的业务实现基线 |
| iOS `sdk` 适配 | `c8a5fb34469684da0277e74456404e180c7b81af` | Apple C ABI、GuiXu KV、Cookie 安全模式、持久化错误边界、下学期课表、多学籍与成绩排名服务接口；远端 `codex/fix/next-semester-resolution` 分支可达 |
| Android `GuiXu-Rust` gitlink | `2481ab378395b5ee6db21021524ad051d98b888f` | 已按需浅拉，并固定为 iOS `Vendor/GuiXu-Rust` 的解析依赖基线 |
| iOS `GuiXu-Rust` 适配 | `387f8105436ba8f8a59f6b6093fb0a2c0ce7b674` | 修复稀疏数字键重开语义并恢复 Apache 2.0 LICENSE/NOTICE 归属；远端 `rust-rewrite` 分支可达 |

基线不得静默替换。Android 参考版本变化时，必须在这里追加新 SHA，并在变更日志说明重新对照了哪些功能与契约。

迁移起点的 iOS 仓库只有两行 README；当前已建立 XcodeGen 工程、SwiftUI 源码、单元/UI 测试、资源、CI、`.gitignore` 和 `AGENTS.md`，`LICENSE` 与正式签名参数仍待确定。早期开发环境为 Windows；当前会话使用 macOS、Xcode 27.0 与 iOS 26.5 Simulator，可执行本机构建和测试。历史 macOS CI 已完成 Simulator 构建测试、Apple device 静态库与未签名 iphoneos App/IPA 构建，物理 iPhone 安装和系统能力仍需用户实测。

## 3. 状态与更新规则

### 3.1 固定状态

| 状态 | 含义 |
| --- | --- |
| 未开始 | 尚未进入该切片 |
| 调研中 | 正在确认 Android 行为、API、平台差异或技术方案 |
| 实现中 | 已开始 iOS 代码实现，尚未达到验收标准 |
| 待验证 | 功能代码已完成，仍缺 macOS、Simulator、真机或真实环境验证 |
| 已完成 | 行为、Android UI 完全一致、构建/测试和证据均满足完成定义 |
| 阻塞 | 存在明确外部依赖，且已记录解除条件 |
| 暂缓 | 经确认当前版本不做，但仍保留在长期范围内 |

### 3.2 每个切片的完成定义

只有同时满足以下条件，功能才能标记为“已完成”：

1. Android 参考行为和 iOS 平台差异已经记录，未照搬已知缺陷。
2. 所有用户可见页面与状态满足 1.4 的 UI 完全一致硬约束，并留有同尺寸逐屏对照证据。
3. 正常、加载、空数据、网络错误及相关登录失效状态均有明确表现。
4. 数据模型、解析、状态机或关键业务逻辑至少有对应单元测试或契约测试。
5. iOS 工程在指定 macOS/Xcode 基线上构建成功，相关测试通过。
6. 需要系统能力的功能已在 Simulator 或真机完成相应验证；支付必须使用受控测试账号或经授权的真实环境验证。
7. 不包含用户密码、Token、Cookie、账号、签名证书或未经批准的敏感信息；获明确批准的支付协议兼容常量必须只位于私有兼容层，其值不得进入日志、回复、文档、诊断或验收证据。
8. 本表已写入验证命令/证据、Commit/PR、最近更新时间，且变更日志已追加记录。

只有单侧截图、只对齐首屏、只有 UI/Mock/占位文件或未经构建的代码不能标记为“已完成”，最多标记为“实现中”或“待验证”。

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
  → 五个支付切片与写操作
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
| Compose `NavHost` / 底栏 | 系统 `TabView` 承载四入口，每个 Tab 使用独立 `NavigationStack`；详情页以系统 toolbar 语义隐藏 Tab Bar |
| ViewModel + StateFlow | `@MainActor` 状态模型；基线允许时使用 Observation，否则使用 `ObservableObject` |
| Retrofit / OkHttp / Gson | `URLSession`、`Codable`、结构化错误与可注入 Transport |
| OkHttp Authenticator / 全局锁 | `AuthSession` actor，统一 Cookie/Token 刷新和并发去重 |
| MMKV / DataStore | 普通偏好使用 `UserDefaults`，结构缓存使用文件或 SwiftData |
| 登录密码 / Token / Cookie | 登录凭据使用 ThisDeviceOnly Keychain 并按用户隔离；支付六位密码绝不持久化，只在安全键盘映射调用栈中短暂存在并立即清空 |
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
| D-003 | Rust crate 是否支持 Apple target、staticlib/XCFramework 及 C ABI/UniFFI | 已完成 spike 与持久化适配 | SDK `18ab4b0` 在原 Simulator/device `staticlib` 基础上补齐 GuiXu 初始化、KV 增删查清、结构化错误、panic 边界和跨 FFI/JNI/WASM 的认证诊断脱敏；本阶段不额外封装 XCFramework，构建脚本按 Apple target 选择静态库 |
| D-004 | Rust 直连 FFI、本地 loopback HTTP 或 Swift `URLSession` 的主数据方案 | 已确定开发期方案 | C ABI 负责生命周期及 GuiXu 持久化/KV；业务请求继续使用带随机 token 的 localhost Rust server + Swift `URLSession`，只开放 loopback，保留未来逐接口直连 FFI 的替换边界 |
| D-005 | 支付协议兼容逻辑部署位置 | 已按产品决策解除客户端实现阻塞 | 以 Android `2c33b0b` 的生产行为为准，允许 iOS 在 App 内执行同等签名与安全键盘映射。Android 已有的客户端协议签名常量只在私有兼容层中存在，值不进入回复、日志、文档或诊断；用户密码仍只短暂位于内存。服务端 broker 可作为未来架构升级，但不再是 PAY-01、PAY-02、PAY-03、PAY-05 的完成前置条件 |
| D-006 | macOS CI、Simulator 设备矩阵与真机验证负责人 | 最终 Simulator、未签名 IPA 与 Release Archive 均通过 | 当前 CI `30697541236` 在 Xcode 26.6（17F113）、iPhone 13 Pro / iOS 26.5 Simulator 上通过 277 个单元测试与 10 个 UI 测试；Artifact `AHUTong-ui-parity-xcresult-87` 为 22,453,461 bytes。设备 run `30697541215` 与 Archive run `30697541230` 成功；物理 iPhone 13 Pro 的真实校园账号数据由用户验证 |
| D-008 | 当前无付费 Apple Developer Program 账号时的真机分发方式 | 已确定开发期方案 | GitHub Actions 只生成未签名 IPA；Apple ID 不进入仓库或 GitHub Secrets；本机使用 Personal Team/Sideloadly 或 AltStore 签名，每 7 天刷新；该方式不等同于 TestFlight/App Store 发布 |
| D-007 | 崩溃上报、灰度、统计与广告方案 | 已确定当前方案 | 当前不集成第三方崩溃、统计或广告 SDK；灰度只向自有端点发送不可逆账号摘要并提供本地兜底；未来新增数据收集必须先更新隐私清单和用途评估 |
| D-009 | Android 三个首启弹窗在 iOS 的同意语义 | 已确定开发期方案 | 隐私政策首先展示并记录接受/拒绝；接受即授权本机 Keychain 保存账密/Cookie 及前台 WebView 续期，但可暂不登录进入体验账户；拒绝也可进入课表体验账户；设置可撤回并删除凭据；免责声明仍需接受，社区说明为可选 |

## 7. 里程碑

| 阶段 | 目标 | 出口条件 | 状态 |
| --- | --- | --- | --- |
| P0 | 契约、安全与工程基线 | 完成关键决策；建立 DTO/golden fixtures；Rust/Swift 数据方案有结论；无敏感信息入库 | 实现中（许可证/正式签名待定） |
| P1 | App 骨架与离线样例 | SwiftUI 四入口、主题、导航、依赖注入、Mock、单测/UI smoke 可在 macOS CI 运行 | 已完成 |
| P2 | 核心闭环 | 登录/退出/恢复会话、课表、首页今日课程、离线缓存、多账号隔离完整 | 已完成 |
| P3 | 教务域 | 成绩/GPA、考试、空闲教室契约与 UI 完整 | 已完成（3 / 3） |
| P4 | 低风险校园服务 | 余额/二维码、失物只读、校历、天气、电话本、学习资料完整 | 已完成 |
| P5 | 写操作与支付 | 失物发布/删除和五个支付切片满足各自的安全、失败恢复与真机验收条件 | 客户端实现已完成；PAY-01～05 均待授权账号与物理 iPhone 验收，真实扣款不由 CI 自动执行 |
| P6 | 平台增强 | WidgetKit、课程提醒、可选 Live Activity、后台刷新与辅助功能完整 | 已完成（WidgetKit、跨周提醒、ActivityKit、前台/时区维护与 Dynamic Type） |
| P7 | 发布 | Release Archive、签名、权限文案、隐私清单、TestFlight/App Store 清单完整 | 工程收口（OPS-01 完成；正式许可证、付费签名/TestFlight 不属于当前 Personal Team 方案） |

## 8. 功能迁移矩阵

单次手动登录改造待验证证据 `E-20260924-05`：用户明确要求只在 App 官方登录页手动输入一次，ADWMH 首次会话与后续过期一律在前台隐藏完成。iOS 移除“必须已有校园卡 Cookie”的门槛，隐藏 WebView 加载校方页面后可从空 Cookie 请求验证码并接收校方新会话 Cookie，再将当次图片送已披露的远端 OCR，向校方提交并用余额只读接口验证；只读校园卡/失物招领请求自动续期一次，写请求不自动重放。失败保留原凭据、展示脱敏原因并允许重试，不自动打开第二登录页。隐私政策升级 v4，原 v3 同意须重新确认；iOS commit `0daa63f` 的 CI `35959882196` 通过 388 个单元测试与 10 个 UI 测试；未签名 IPA #123 run `35959882205`（6,764,221 bytes，SHA-256 `DBEA710E81011A32380BBF466AE6E8E307AE42BA517F19CBC13BD270F9BB4BD7`）和 Release Archive `35959882197` 成功。授权 iPhone 真机仍待验证。

远端 OCR 诊断证据 `E-20260924-03`：#121 真机反馈已越过验证码图片获取，进入 `openahu.org/ocr/captcha` 阶段；Android `develop` 同样使用此 HTTPS 端点和 JSON `result` 字段，但 iOS 原请求仅等待 10 秒并统一宣称 JPEG。iOS 改为按图片签名选择上传 MIME、JPEG 对齐 Android 的 `image/jpg`，OCR 请求最长等待 20 秒且隐藏总流程仍限 30 秒；失败只报告超时、网络、重定向、HTTP 状态、响应格式或非四位结果，绝不显示图片或识别内容。`CampusCaptchaRecognizerTests` 使用 URLProtocol 本地夹具验证这些边界；最终 CI `35956666651` 通过 384 个单元测试与 10 个 UI 测试，未签名 IPA #122（6,782,133 bytes，SHA-256 `97ADAA4A30943A2324F4BF4496A29442F4F6AB99F553BA22C2FECA3B79CF3948`）和 Archive `35956666648` 成功；#122 真机曾反馈远端 OCR 网络失败，同网络 Safari 一度无法打开站点，稍后网络恢复，用户确认无需继续修复；自动登录最终效果仍待复验。

本轮验证码取图修复证据 `E-20260924-02`：授权真机反馈隐藏续期在“获取验证码图片”阶段失败，旧 iOS 实现于校方页面执行 JavaScript `fetch`，而 Android `develop` 使用携带校园会话 Cookie 的原生 GET `/remind/authcode`。iOS 改为同域原生 GET、禁止跨域重定向、限制图片大小和格式、仅传当前校方 Cookie、合并响应 Cookie；远端 OCR 仍只接收图片且不附带凭据。`CampusCardCaptchaClientTests` 以 URLProtocol 本地夹具覆盖成功、Cookie、缺失会话、重定向、HTTP 失败和非图片；macOS CI `35956666651` 通过 384 个单元测试与 10 个 UI 测试；真机已证明能进入远端 OCR 阶段；脚本策略是否为旧根因仍未证实。

本轮修复证据 `E-20260924-01`：iOS commit `d0ccac1` 对照 Android `develop` `e7d27ae` 的校园卡图像点按行为，实现内联与全屏二维码点击强制刷新付款码、成功后刷新余额；失物招领目录及列表接受校方只读成功码 `10000`，写入接口保持原判定。`LostFoundTests` 使用 URLProtocol 本地夹具重现 `操作成功!` 响应，`CampusCardInteractionTests` 与 UI smoke 覆盖二维码再次点击；校园卡隐藏续期阶段失败只展示脱敏临时 Toast。未签名 IPA run `35898534671`（#118，6,770,903 bytes，SHA-256 `3ED394488EE62325EE014D8C31E232CA591A724529E6278BB43CC4490D04DE06`）与 Archive `35898534959` 已成功；首轮 CI `35898534602` 的 373 个单元测试全过，唯 1 项 UI smoke 因旧 `Image` 断言未适配二维码的新 `Button` 辅助功能节点而失败；`ab5c356` 改用可点击按钮断言并补充 VoiceOver 标签后，最终 CI `35901490865` 通过 373 个单元测试和 10 个 UI 测试。最新未签名 IPA run `35901490892`（#120，6,770,987 bytes，SHA-256 `1710D551A1E70CDBD99644E7025691CC8820A52F869B866F6B1A16FA1F05BE11`）及 Archive `35901490864` 均成功，物理 iPhone 上的真实验证码、OCR 与校方会话恢复仍待用户验证。

说明：Android 路径均相对于 Android 子仓根目录。`—` 表示尚无验证或提交证据。完成行共享证据 `E-20260714-01`：Android 固定参考 SHA `2a30a54`，仅含测试/固定数据的证据分支 commit `b063581`，CI `29327068093` 与 29 张 1170×2532 PNG 的 UI run `29327068134` 均成功；iOS code commit `6561f25` 的 CI `29331379333` 在 Xcode 26.5（17F42）、iPhone 13 Pro / iOS 26.5 Simulator 上通过 68 个单元测试、2 个 UI 测试，Artifact `AHUTong-ui-parity-xcresult-37` 含同尺寸 29 张 PNG；设备 run `29331379344` 成功上传 3,740,282 bytes 的 `AHUTong-unsigned-ipa-37`。两侧正常、加载、空、错误、弹窗和详情截图已逐屏审查，允许差异仅限第 9 节记录的平台边界。

本轮新增完成行共享证据 `E-20260715-01`：Android 产品参考仍固定为 `2a30a54`，证据分支仅增加测试与确定性 fixture，commit `887a0c5` 的 CI `29351110964` 和 UI run `29351111083` 均成功，Artifact `AHUTong-android-ui-baseline-19` 含 43 张 1170×2532 PNG；iOS code commit `77a5ae5` 的 CI `29353937788` 在 Xcode 26.5（17F42）、iPhone 13 Pro / iOS 26.5 Simulator 上通过 87 个单元测试、3 个 UI 测试，Artifact `AHUTong-ui-parity-xcresult-46` 含同尺寸 43 张 PNG 且无缺图；设备 run `29353938071` 上传 4,211,678 bytes 的 `AHUTong-unsigned-ipa-46`，SHA-256 为 `81F454EE79F2FB343E49BEB39DE7E05CA6E9B5B79B0FC7B7D5A1B7561466FF20`，包内确认包含 `AHUTongWidget.appex`。新增空闲教室、失物列表/详情/发布、Widget 预览、提醒开关及登录/数据三态均完成双端逐屏审查；真实校园账号和物理 iPhone 只作为部署环境回归，不冒充已执行证据。

收口证据 `E-20260715-02`：Android 产品参考继续固定为 `2a30a54`，证据分支 commit `fc150b0` 只扩展 UI 自动化，Android CI `29359831800` 与 UI run `29359831897` 均成功，Artifact `AHUTong-android-ui-baseline-20` 含 48 张 1170×2532 PNG；新增校园卡充值正常/确认弹窗、浴室正常、电控正常和隐藏 Debug 五屏已逐张目视检查。iOS commits `c091244`、`eb240cc`、`eae0cd8`、`510b292`、`5468999`、`edfd219` 已分别完成支付/运维、调用系统 Liquid Glass API 的自绘底栏、移除录屏遮罩、站内贡献名单、支付按钮唯一标识，以及 Apple GuiXu/旧缓存迁移/可见 Debug 入口。SDK `e826156` 补齐 Apple GuiXu C ABI 与 Keychain-only Cookie 模式；Rust SDK 5 项、固定 GuiXu 5 项本地测试，以及 CI `29366676954` 的 117 个单元测试、4 个 UI 测试均通过。Artifact `AHUTong-ui-parity-xcresult-54` 含 54 张 1170×2532 PNG，无失败关联附件；设置页可见 Debug、Debug 页面和站内贡献名单已目视复核。设备 run `29366676886` 上传 `AHUTong-unsigned-ipa-54`，其中 IPA 为 4,515,159 bytes，SHA-256 `5b268279de7059e8c7dda4c1d0adb1628591c0245d6d8053de17834f3b6fb318`；Archive run `29366676870` 上传 `AHUTong-release-readiness-8` 并通过 App/Widget、双隐私清单、dSYM 与敏感信息边界校验。支付截图为不可扣款 Mock，只证明客户端 UI/状态机，不替代 D-005 服务端网关与授权环境验收；该版底栏只是系统玻璃材质作用于自绘结构，不作为原生 `UITabBar` 证据。

图标回归证据 `E-20260715-03`：对照 Android 固定基线的 `lost_and_found.xml` 与 `Icons.Outlined.Feedback`，iOS commit `53cb7fd` 移除不存在的 `questionmark.bag`、`bubble.left.and.exclamationmark`，失物招领改为稳定的 `bag` + `questionmark` 分层组合，意见反馈改为 `exclamationmark.bubble`。CI `29369377322` 在 iPhone 13 Pro Simulator 上通过 118 个单元测试和 4 个 UI 测试；`AndroidParityIconTests` 确认三个底层 SF Symbols 均可创建，`settings.feedback` UI 入口断言通过。Artifact `AHUTong-ui-parity-xcresult-55` 含 54 张 PNG 且无失败关联附件，`06-tools` 已目视确认蓝色包与问号完整显示；设置主屏截图下部受浮动底栏遮挡，因此反馈图标以专项符号测试和 UI 入口断言作为可复现证据，不虚构目视结论。未签名 IPA run `29369377575` 与 Release Archive run `29369377896` 同时成功。

全量复查收口证据 `E-20260715-04`：Android 产品基线继续固定为 `2a30a54`，iOS 最终代码 commits `565671e`、`a0d4855`、`444d2d3`、`0754440`、`7590212`、`7086948`、`18f96d5`，SDK `1177864f4063b65220dc18c6742fb5d7ebe45ae5` 已推送。最终 CI `29391015504` 在 Xcode 26.5、iPhone 13 Pro / iOS 26.5 Simulator 上通过 132 个单元测试和 5 个 UI 测试；原生导航专项实际执行左边缘拖动与两个内容坐标有限重试的内容区域拖动，两条路径均返回工具页。Artifact `AHUTong-ui-parity-xcresult-62` 为 18,811,420 bytes，SHA-256 `e1c8410c1299176e9a8f2ae99a3474265aaebcacbb9fd721937ed758b7e5a6f4`。未签名 IPA run `29391015407` 上传 `AHUTong-unsigned-ipa-62`；其中 IPA 为 5,496,416 bytes，SHA-256 `EB21B418F0B2839EBD02E3CA2F30CF13BB370D5979FD84F9AF1EC77896A6F051`。Release run `29391015433` 上传 9,592,955 bytes 的 `AHUTong-release-readiness-16`，完成 App/Widget/ActivityKit、AppIcon、隐私清单、dSYM 与敏感材料边界审计。PhotoKit、定位、通知和 Live Activity 的物理效果仍需用户真机部署回归；这不替代三类真实支付的 D-005 外部验收。

原生底栏修复证据 `E-20260716-01`：根 App Shell 已删除 `LiquidGlassBottomBar` 的 `HStack + Button` 自绘实现，改由系统 `TabView` 生成 `UITabBar`；四个入口各自持有 `NavigationStack`，详情页使用 `.toolbar(.hidden, for: .tabBar)` 交给系统隐藏/恢复，四个一级页删除旧覆盖栏所需的 96pt 补偿。代码 commits `0a8f855`、`4bb2bab` 已推送。最终 CI `29432910807` 在 Xcode 26.5、iPhone 13 Pro / iOS 26.5 Simulator 上通过 132 个单元测试和 5 个 UI 测试；UI 自动化明确从 `XCUIElementTypeTabBar` 下操作四个系统标签按钮，并验证详情页隐藏、两种原生返回手势及返回后底栏恢复。Artifact `AHUTong-ui-parity-xcresult-64` 为 19,622,549 bytes，SHA-256 `c99bfa483f0a948a6c79511dfc7ec6b3d4bd67c8958fa23178a6e23811fcea24`，含 54 张截图且无失败关联附件；首页截图已目视确认系统 Liquid Glass 胶囊、系统选中态和四入口完整。未签名 IPA run `29432910913` 上传 `AHUTong-unsigned-ipa-64`，其中 IPA 为 5,470,527 bytes，SHA-256 `031285173E231B3659DBF417C8DD9751AE9DB34E033ECFB09236148905254403`；Release run `29432910832` 上传 9,547,511 bytes 的 `AHUTong-release-readiness-18`。首次 CI `29431825512` 的 3 条旧 identifier 失败作为测试迁移诊断保留，不计为最终验证。

液态玻璃偏好收口证据 `E-20260716-02`：偏好页面已删除“液态玻璃”整个区块，不保留开关或“跟随系统”说明行；代码中无 `visual.liquid-glass`、`preferences.liquid-glass` 或 `preferences.native-tab-bar` 运行时入口。Commit `d5d791f` 已推送。最终 CI `29435300302` 在 Xcode 26.5、iPhone 13 Pro / iOS 26.5 Simulator 上通过 132 个单元测试和 5 个 UI 测试，三个否定断言确认标题、旧开关和旧说明节点均不存在；Artifact `AHUTong-ui-parity-xcresult-65` 为 19,539,052 bytes，SHA-256 `1ea361115a94691ed9c8fd8dd9f094c89b1cf7a4f62fe2cc7a72612f633ef4c5`，偏好页截图已目视确认通知增强后直接进入主题颜色。未签名 IPA run `29435300525` 上传 `AHUTong-unsigned-ipa-65`，其中 IPA 为 5,465,652 bytes，SHA-256 `D517EA930E37825A62436A6B3262E95631469511191C954951C792EBE0CFBA03`；Release run `29435300113` 上传 9,539,495 bytes 的 `AHUTong-release-readiness-19`。

学校官方支付入口证据 `E-20260717-01`：代码 commits `df88d87`、`ac5e1d0` 已推送。三类生产页使用 `SFSafariViewController` 打开 `ycard.ahu.edu.cn` 同域 CAS/校园卡入口，页面明确说明本地表单不会随跳转提交，打开/关闭页面不代表扣款成功；Debug 诊断仍把原生生产网关标为未配置。最终 CI `29439249505` 在 Xcode 26.5、iPhone 13 Pro / iOS 26.5 Simulator 上完成无账号、无金额、无订单的 HTTPS HEAD/302 探测，并通过 133 个单元测试与 5 个 UI 测试；Artifact `AHUTong-ui-parity-xcresult-67` 为 19,534,427 bytes。未签名 IPA run `29439249117` 上传 `AHUTong-unsigned-ipa-67`，IPA 为 5,480,883 bytes，SHA-256 `CA5203812ECA32399A32F0627D97CF7756A99449CEB5CCDDAFB9D70C382A62A2`，产物侧校验文件一致；Release run `29439249504` 上传 9,567,090 bytes 的 `AHUTong-release-readiness-21` 并通过敏感材料扫描。首次 CI `29437746489` 中原 132 个单元测试与 5 个 UI 测试均通过，仅新增 URL 测试把 Foundation 标准化后的 `/plat` 错写成 `/plat/`，修正后复验通过；该诊断不冒充产品故障。真实登录、业务列表、最终确认和账单变化仍须用户在物理 iPhone 13 Pro 上验证，未执行任何自动扣款。

设置 Debug 入口收口证据 `E-20260717-02`：代码 commits `ec4f21a`、`64cc7df`、`4f00e8e` 已推送。设置“关于”列表删除可见 `Debug` `NavigationLink` 和 `settings.debug` 标识，完整诊断页及 `showsDebug` 导航保留；App 信息卡合并为单一辅助功能元素，UI 自动化同时断言列表无 Debug 按钮/文案，并用系统 8 连点手势进入 `operations.debug.screen`、保存第 33 屏截图。最终 CI `29520243365` attempt 3 在 Xcode 26.5、iPhone 13 Pro / iOS 26.5 Simulator 上通过 133 个单元测试与 5 个 UI 测试；Artifact `AHUTong-ui-parity-xcresult-70` 为 19,682,221 bytes。未签名 IPA run `29520243324` 上传 `AHUTong-unsigned-ipa-70`，IPA 为 5,487,372 bytes，SHA-256 `3742D1D763F73C3D89E151172C27581FFA7FC3EDCD64AE6F4CA97920D34A633B`，产物校验文件一致；Release run `29520243338` 上传 9,571,856 bytes 的 `AHUTong-release-readiness-24`。诊断记录：CI `29517210090` 首次因 SwiftUI 标识传播导致测试多命中，`29518859957` 因逐次 `tap()` 等待 idle 超过 Android 同款 1 秒计数阈值而未解锁；最终改用系统合成 8 连点。最终 run 的 attempts 1～2 中隐藏入口均已通过，失败仅为既有课表/考试长链路的不同等待点偶发超时，attempt 3 同 commit 全绿；不把失败 attempt 冒充最终证据。

设置点击反馈收口证据 `E-20260717-03`：代码 commit `c68ff9a` 已推送。设置首页、偏好开关、主题色、许可证、贡献者及执行型按钮统一使用 `SettingsPressFeedbackStyle`；触摸按下立即显示明暗高亮、0.985 缩放并触发一次轻触觉，开启“减弱动态效果”时取消缩放但保留非动态反馈。`SettingsInteractionTests` 的 2 项专项测试锁定常规按压态与减弱动态效果语义。最终 CI `29524972678` 在 Xcode 26.5、iPhone 13 Pro / iOS 26.5 Simulator 上通过 135 个单元测试与 5 个 UI 测试；Artifact `AHUTong-ui-parity-xcresult-71` 为 19,687,342 bytes。未签名 IPA run `29524973286` 上传 `AHUTong-unsigned-ipa-71`，IPA 为 5,493,558 bytes，SHA-256 `059A5CEF3E9A149F3E31964AE2FA7382DFF819573072030A43B4F4F47839969F`，产物校验文件一致；Release run `29524972714` 上传 9,582,445 bytes 的 `AHUTong-release-readiness-25`。Simulator 可验证按压视觉与导航，但没有物理触觉，轻触觉仍由用户在 iPhone 13 Pro 上完成部署回归。

课表左右分页收口证据 `E-20260717-04`：对照 Android `Schedule.kt` 的 `HorizontalPager`，iOS commits `aa4387f`、`ce732e0`、`7589911` 将课表主体改为原生 page-style `TabView`，完整承载 1～20 周并让左右拖动、顶部周次和“回到当前周”共享选择状态；每页按自身周次计算日期、课程显隐和非本周样式。首次 CI `29526843733` 中新增左右滑动专项已通过，但旧课程详情用例暴露分页辅助功能标识冲突；第二次 CI `29527873374` 进一步证明父级 `schedule.week-page.*` 被 SwiftUI 传播到课程按钮，且同时出现两个课表外既有长链超时。删除父级标识后，最终 CI `29529374996` 在 Xcode 26.5、iPhone 13 Pro / iOS 26.5 Simulator 上通过 138 个单元测试与 6 个 UI 测试；专项真实执行左滑第 1→2 周、右滑第 2→1 周，并在滑动前后确认课程卡可见可导航。Artifact `AHUTong-ui-parity-xcresult-74` 为 19,689,203 bytes。未签名 IPA run `29529375018` 上传 `AHUTong-unsigned-ipa-74`，IPA 为 5,504,028 bytes，SHA-256 `F5972A453283289421908A4334E48524FCF8F2026B1AE87F0FF07FC2DD4F1B8A`，产物校验文件一致；Release run `29529375330` 上传 9,597,304 bytes 的 `AHUTong-release-readiness-28`。物理 iPhone 13 Pro 的连续分页手感仍由用户部署回归。

考场查询收口证据 `E-20260717-05`：根因是 SDK 的考场 HTML 解析器把 Rust `regex` 不支持的负向前瞻 `(?!...)` 交给 `Regex::new(...).unwrap()`，首次解析真实考场表格会触发运行时 panic；旧逻辑还依赖固定的标签换行和属性顺序，并会把 JSON 字符串座位号经 `Value::to_string()` 变成带引号文本。SDK commit `ebf7024` 改为逐行提取当前教务表格，兼容换行、属性乱序、单双/无引号属性、`var`/`let`/`const` 学生考试列表，以及字符串/数字座位号；本地 `cargo test -- --nocapture` 9 项全绿，其中 2 项为新增真实形态 HTML 契约。iOS commit `1f23ee2` 为 `CampusExam` 增加数字/字符串座位号、缺失地点与多形态结束状态容错，重试按钮保持 Demo 模式，并为考试卡增加稳定 UI 标识；`CampusExamDecodingTests` 2 项专项通过，主屏 UI 自动化进入考场查询并确认“操作系统”考试卡。最终 CI `29531844860` attempt 3 在 Xcode 26.5、iPhone 13 Pro / iOS 26.5 Simulator 上通过 140 个单元测试与 6 个 UI 测试，Artifact `AHUTong-ui-parity-xcresult-75` 为 19,726,197 bytes；attempts 1～2 中考场专项也均通过，仅分别遭遇既有 Simulator 进程终止与工具页长链时序抖动，不计作最终证据。未签名 IPA run `29531844760` 上传 `AHUTong-unsigned-ipa-75`，IPA 为 5,509,830 bytes，SHA-256 `EE2CBF3B70E58C312C4B8B2EAFC64DBB5DCDEB86D0B0EA7B5672424F0AB9CEBA`，产物校验文件一致；Release run `29531844893` 上传 9,607,880 bytes 的 `AHUTong-release-readiness-29`。Simulator 与 Demo 数据证明解析、解码和 UI 链路，真实教务数据仍须用户在物理 iPhone 13 Pro 使用校园账号刷新验证。

课表总览/下学期收口证据 `E-20260717-06`：共同交互根因是 iOS 把 `Toggle` 放进 SwiftUI `.alert` actions，而系统 Alert 只保证按钮动作，两个开关因此不可可靠点击；下学期数据层还把目标学期 ID 固定写成“当前 ID + 20”，编号间隔变化时会请求错误学期。iOS commit `b78bcde` 改为 310pt 原生 Sheet，两个设置项均采用 Android 同款整行可点击按钮、可视开关、按压高亮/缩放/轻触觉及“开启/关闭”辅助功能值；总览按星期/开始节次/时长纵向分组同时间课程，显示周次范围并弱化非本周课程；下学期使用独立 Demo/真实数据，`.task(id:)` 取消过期加载以避免快速切换被旧请求覆盖，“回到当前周”会先退出预览。SDK commit `c8a5fb3` 从页面 `semesters` 实际列表按学期顺序选择下一 ID，仅在列表缺失时回退旧 offset；`cargo test -- --nocapture` 11 项全绿，其中 2 项覆盖非固定间隔和倒序列表。最终 CI `29537917170` 在 Xcode 26.5、iPhone 13 Pro / iOS 26.5 Simulator 上通过 142 个单元测试与 6 个 UI 测试；`ScheduleWeekNavigationTests` 5 项通过，UI 专项连续验证左右分页、总览从“关闭”变“开启”并出现非本周课程、下学期从“关闭”变“开启”并替换为下学期课程。Artifact `AHUTong-ui-parity-xcresult-78` 为 19,625,818 bytes。未签名 IPA run `29537917146` 上传 `AHUTong-unsigned-ipa-78`，IPA 为 5,556,882 bytes，SHA-256 `061FB4B210520A17D07163DD931607F9D957C63421AD9B461D0EC51EEBCF645D`；Release run `29537917347` 上传 9,699,477 bytes 的 `AHUTong-release-readiness-32`。首次代码 run `29536631558` 的 142 单测全绿，但暴露原 Toggle 点按仍保持关闭，同时既有工具页长链偶发未找到成绩入口；改为唯一整行按钮后最终同功能提交全绿。真实下学期是否已发布及具体课程仍须用户校园账号在物理 iPhone 13 Pro 刷新验证。

Android 3.2.0 复审收口证据 `E-20260726-01`：产品参考更新为远端 `2c33b0b`，相对旧基线新增 ACA-04 教学评价、PAY-04 招商银行充值、PAY-05 网费充值三个独立切片，并重新对照课表/首页/成绩/考试/校园卡/电话本/天气/资料库/设置/运维十个既有切片。iOS commits `02b3042`、`e6b4825`、`c02c168`、`61cee26` 已推送，补齐真实评教 API 与提交、招商银行 Token/Cookie/WebView 安全链路、网费账户读取和官方入口、资料库 LFS/Markdown/下载、考试与首页视觉、天气升级兼容、失物“我的发布”、真实隐私说明、GuiXu 许可证，以及浴室/电控本地交互；评教只清理服务路径 Cookie，不删除共享 CAS 根 Cookie。Windows 本地 `Vendor/sdk cargo test --locked` 11 项、`Vendor/GuiXu-Rust cargo test --locked` 5 项及 `git diff --check` 通过。最终 CI `30211540807` 在 Xcode 26.5（17F42）、iPhone 13 Pro / iOS 26.5 Simulator 上通过 203 个单元测试与 9 个 UI 测试，Artifact `AHUTong-ui-parity-xcresult-82` 为 21,950,639 bytes；未签名 IPA run `30211540786` 上传 `AHUTong-unsigned-ipa-82`，IPA 为 6,408,389 bytes、SHA-256 `70C71F78E94536E4879CD21DB557BC3DDE8F4940962F1C46763300C92EAA263F`；Release run `30211540817` 上传 11,251,185 bytes 的 `AHUTong-release-readiness-36`。诊断 run `30209835791` 暴露旧天气断言和实时 IP 天气输入，`30210686620` 暴露工具页切换时序与命令行覆盖未被读取；最终以 Android 雨雪雹优先规则、显式调试端点参数和目标元素等待修复，不用盲目重跑冒充通过。PAY-04 仍需要授权校园账号/物理 iPhone；PAY-01/02/03/05 原生扣款仍不具备 D-005 安全网关与 R-004 沙箱，未执行任何自动扣款。

支付与诊断安全收口证据 `E-20260801-01`：Android 产品参考继续固定为 `2c33b0b`。iOS commits `1e01069`、`c87c10a`、`9721ed8`、`1b47a34` 已推送，PAY-01～03 分别接入真实只读账户、浴室余额和电控四级数据链，PAY-04 隐藏验收改为无 WebView/脚本/请求体的原生 HEAD 手工跳转链，并增加无凭据官方入口探测；支付状态机在创建订单前持久化功能类型、幂等键和不可逆请求指纹，响应丢失或进程重启后复用同一键，不保存原始账号、金额或授权材料。SDK `18ab4b0` 已推送，Windows 本地 `cargo test --locked` 16 项与 `cargo test --locked --features server` 18 项全绿；Swift、Rust 与 GuiXu 的错误/日志边界完成认证头、Cookie、Token、URL 参数、编码空格、畸形转义及 Basic/Bearer/Digest 脱敏。最终 CI `30697541236` 在 Xcode 26.6（17F113）、iPhone 13 Pro / iOS 26.5 Simulator 上完成实时无凭据 HEAD/302 契约探测，并通过 277 个单元测试与 10 个 UI 测试；Artifact `AHUTong-ui-parity-xcresult-87` 为 22,453,461 bytes。未签名 IPA run `30697541215` 上传 `AHUTong-unsigned-ipa-87`，其中 IPA 为 6,728,951 bytes、SHA-256 `7E97FF9E612854AF536FAF538C6237F489754CD35B1D4E5F9E56DBFB651ED8CE`；Release run `30697541230` 上传 11,842,090 bytes 的 `AHUTong-release-readiness-41`，仓库/二进制敏感材料、App/Widget、双隐私清单和 dSYM 检查通过。诊断 CI `30695338471` 暴露 URLProtocol 重定向模拟、脱敏占位符和两个 iOS 26 UI 层级问题；`30696548830` 进一步暴露 Darwin 对目录 URL 的 `/plat` 规范化及 Alert 父子镜像按钮，均按真实根因修复，不以重跑冒充通过。客户端实现覆盖仍为 26 / 26（100%），Android 生产行为 22 / 26（84.6%），严格完成 21 / 26（80.8%）；PAY-04 仍待授权账号物理 iPhone 证据，PAY-01/02/03/05 原生扣款仍受 D-005、R-003、R-004 阻塞，本轮未发起任何自动扣款。

支付原生生产协议重审收口证据 `E-20260801-02`：Android 唯一参考固定为 `2c33b0bb923f197f1d209cb58589a6b5d052cd9f`，未使用旧 worktree 的 `2a30a54`。iOS commits `4e7d58e`、`20e4757`、`c15123b` 已推送：PAY-01 完成卡账户查询、Android 同规则签名建单、银行卡最终提交、余额刷新和支付宝白名单小程序路径；PAY-02 完成 `feeitemid` 409/430、`paystep=0` 建单、固定安全键盘兼容映射、`paystep=2` 提交和余额刷新；PAY-03/PAY-05 完成签名建单、每订单动态键盘材料与订单绑定、最终提交及余额刷新，PAY-05 还包含入口预热和账户查询。通用学校官方页及 `SafetyBlockedPaymentGateway` 已从正式链路删除。订单在网络写请求前持久化阶段、拿到 `orderid` 后立即持久化功能/方式/订单号，未知结果闭锁原订单且不自动重建或重提；六位原始密码只短暂存在内存并在提交/退出路径清空。Android 已有的客户端协议签名常量只保留在私有兼容层，本文不记录其值。最终 CI `30706286051` 在 Xcode 26.6（17F113）、iPhone 13 Pro / iOS 26.5 Simulator 上通过 333 个单元测试与 9 个 UI 测试，Artifact `AHUTong-ui-parity-xcresult-91` 为 22,079,678 bytes；未签名 IPA run `30706286050` 上传 Artifact `AHUTong-unsigned-ipa-91`（ID `8820461167`，6,797,622 bytes），其中 IPA 为 6,837,668 bytes、SHA-256 `DA780F9B4C7AAC3444A8816A6E60F19CC8DFC5A92291C6C003807FE36AF11C9C`，随附校验文件一致；Release run `30706286068` 上传 `AHUTong-release-readiness-45`（ID `8820460278`，12,064,303 bytes），App/Widget 的 Info.plist、隐私清单、dSYM 与敏感材料隔离检查全部通过。首轮 CI `30704350520` 暴露 macOS URLProtocol 将 POST 表单呈现为 `httpBodyStream` 及测试防漂移校验录入不完整，修复未改变生产协议材料；随后重审继续修正 PAY-01/PAY-02 与 PAY-05 的 Android 结果边界，并补齐 PAY-03/PAY-05 双订单动态材料隔离测试。所有自动化均由 URLProtocol/Mock、应用级禁写开关和 runner 域名阻断保护，未连接真实扣款接口、未创建真实订单。客户端实现与 Android 生产行为对齐均为 26 / 26（100%）；严格完成仍为 21 / 26（80.8%），PAY-01～05 只待用户在物理 iPhone 13 Pro 手动完成授权账号小额验收。

登录 Session 过期收口证据 `E-20260802-01`：Android 唯一参考固定为 `2c33b0bb923f197f1d209cb58589a6b5d052cd9f`。SDK commits `e6c1df2`、`64b3564` 已推送：共享认证响应边界在业务解析前识别 401/403、最终 CAS/JWXT 登录 URL、`tologin`/`refer` 跳转与登录表单，返回 typed `campus_session_expired`，本地 HTTP 服务只把该类型稳定映射为 401；网络、学校 5xx 和普通解析错误不误报。iOS commits `d194f9d`、`46b481c`、`bc35276` 已推送：`SessionRefreshCoordinator` 以共享 Task 完成 App 级 single-flight，canonical 学号统一 Keychain 存取，冷启动与 Rust/Swift 直连、校卡 Token、网费和 CMB 共用同一刷新能力；GET/HEAD 和明确只读 POST 最多重试一次，支付建单、动态键盘和最终提交不自动重放。最终 CI `30710319015` 在 Xcode 26.6、iPhone 13 Pro / iOS 26.5 Simulator 上通过 Rust 25 项、Swift 349 个单元测试与 9 个 UI 测试，Artifact `AHUTong-ui-parity-xcresult-94`（ID `8821874043`，22,273,912 bytes）；未签名 IPA run `30710319019` 上传 `AHUTong-unsigned-ipa-94`（ID `8821691878`，6,836,952 bytes），Archive run `30710318991` 上传 `AHUTong-release-readiness-48`（ID `8821692798`，12,125,629 bytes）并通过隐私清单和敏感边界审计。首轮 CI `30709728728` 的 346 个 Swift 单测已通过，但 UI 提醒用例留下持久开关，使后续 demo 启动误触发真实课表维护并收到认证通知后回到登录页；`bc35276` 禁止 demo/CI 的真实维护请求、隔离生产认证通知，并在 runner 阻断全部校园登录与支付域名后得到最终全绿结果，不以重跑替代修复。物理 iPhone 仍需人工验证真实账号的 Session 过期恢复、旧版仅有 Snapshot 时的一次性提示及支付入口刷新不重复写请求。

> `E-20260726-01`、`E-20260801-01` 及对应历史变更日志记录的是当时的实现和判断；教学评价已于 2026-09-22 被整体移除，不再代表当前 iOS 范围。其中“安全网关阻塞、官方页面兜底”的结论已被 D-005、PAY-006 与 `E-20260801-02` 取代，不代表当前支付状态。

| ID | 功能切片 | Android 参考 | iOS 目标 | 优先级 / 依赖 | 状态 | 核心验收 | 验证 / Commit | 更新 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| APP-01 | App Shell、四入口与统一状态 | `ui/screen/Main.kt`、`BottomNavBar.kt` | `App/`、`Core/DesignSystem/` | P1 | 已完成 | 主页/课表/小工具/设置顺序、图标、文案、选中态、Android 色板/卡片/标题/搜索组件和统一页面背景保持不变；按用户显式覆盖，底栏由系统 `TabView`/`UITabBar` 承载，iOS 26+ 自动采用系统 Liquid Glass；每个入口保留独立导航栈，详情页由系统隐藏底栏；冷启动本地会话就绪即进入首页，网络校验不阻塞开屏；最终 UI smoke 见 E-20261014-01。 | 原双端对照见 `E-20260714-01`；系统 Tab Bar 类型、四标签、隐藏/恢复和双返回手势最终回归见 `E-20260716-01`；Commits `0a8f855`、`4bb2bab`；2026-10-14 本机 401 单测 + 2 UI 回归通过，见 `E-20261014-01`；2026-10-19 原生四标签、顺序/选中语义及无玻璃偏好入口复核见 `E-20261019-02`；本轮以 Android 实际路径修正四图标、App 图标开屏及默认动态效果，见 `E-20261019-03` | 2026-10-19 |
| AUTH-01 | 启动、三份协议与首登流程 | `ui/screen/Splash.kt`、`ui/screen/setup/*` | `Features/Onboarding/` | P1 / APP-01 | 已完成 | Android 对话框几何、内容滚动区、按钮和三页标题顺序已对齐；同意状态持久化，拒绝与再次查看路径明确 | `AgreementConsentStoreTests` 3 项通过；双端首启三弹窗证据见 `E-20260714-01`；Android 非活动旧弹窗残影不复制，见第 9 节；Commits `430bd45`、`d15a207`、`6561f25` | 2026-07-14 |
| AUTH-02 | 登录、会话恢复、过期重登与退出 | `Login.kt`、`LoginViewModel.kt`、`AutoLoginInterceptor.kt`、`TokenAuthenticator.kt`、`sdk/*` | `Core/Auth/`、`Core/CampusCore/`、`Core/Networking/`、`Features/Login/` | P2 / D-003、D-004 | 待真机验证 | 隐私 v4 同意后以官方可见 WebView 首登，也可点“暂不登录”进入体验账户并跨启动保持；账密/Cookie 只入 ThisDeviceOnly Keychain；教务过期时前台隐藏 WebView single-flight 续期。ADWMH 首次与后续均在前台隐藏 WebView 建立校方会话，即使没有历史 Cookie 也以同域原生 GET 获取验证码并接收新会话 Cookie，只将图片发往 `https://openahu.org/ocr/captcha` 识别并用同一 `/user/login` 续期，失败提示重试，不打开第二登录页。Keychain 会话快照统一使用 SDK 的扁平 Cookie 列表，仅在识别为原生 NDJSON 且转换非空时迁移旧 Cookie 存档，离线缓存不被空数组覆盖；写请求不重放；隐藏续期失败暂显示脱敏阶段 Toast；本地 Cookie 初始化后先开放缓存身份，再完成网络校验；退出、重新登录和体验切换使旧校验失效，避免异步恢复旧身份；临时隐藏续期失败及重复过期不再清理凭据，首次校验和业务读取保存轮换 Cookie，换账号隔离旧 Cookie | `CampusCardLoginClientTests` 覆盖登录字段与失败响应，`CampusSessionStoreTests` 新增旧快照迁移；373 个单元测试已通过，旧快照离线保护见 `E-20260924-01`；最终 macOS CI `35901490865` 全绿，取图修复与 OCR 诊断见 `E-20260924-02`、`E-20260924-03`；隐私 v4 与首次校园服务隐藏登录见 `E-20260924-05`（CI `35959882196` 全绿）；授权账号真机仍待验证；2026-10-14 本机 401 单测 + 2 UI 回归通过，见 `E-20261014-01`；2026-10-19 本轮维护与待验边界见 `E-20261019-01` | 2026-10-19 |
| SCH-01 | Course 模型、周次解析、API 与离线缓存 | `data/model/Course.java`、`CurrentWeekResolver.kt`、`SdkDataSource.kt`、`AHUCache.kt` | `Core/Models/`、`Features/Schedule/Data/` | P2 / AUTH-02 | 待验证 | 真实账户保留 cache-first/refresh/stale-cache，并同步不含学号的体验课表副本；体验账户绝不请求 CampusCoreAPI，可导入最大 1 MB/500 门课程的 v1 JSON，只接受当前/下学期并原子覆盖；Widget 继续读取本地快照；只解析明确的教学周字段，拒绝学期 ID/布尔值/无效数字；按账号和学期保存周数与日期锚点，离线按周一推进。 | `ExperienceScheduleStoreTests`、拒绝隐私 UI 路径与原课表回归待 macOS CI；2026-10-14 本机 401 单测 + 2 UI 回归通过，见 `E-20261014-01` | 2026-10-14 |
| SCH-02 | 课表 UI、课程详情与设置 | `main/Schedule.kt`、`ScheduleViewModel.kt`、`main/schedule/*` | `Features/Schedule/` | P2 / SCH-01 | 已完成 | 切换 Tab 保留所选周、20 周左右分页、真实日期、单双周、重叠课程、总览、下学期、课程详情和全状态完整；新增 Android 3.2.0 同款地点缩写、周次范围及总览可读文本；日期使用同一校园日历和周数锚点；周日不提前换周，回到前台自动推进日期；未知周数/下学期起始日期显示占位而不伪造日期；旧请求不覆盖下学期预览。 | 原功能证据见 `E-20260714-01`、`E-20260717-04`、`E-20260717-06`；`ScheduleTextFormatter` 与全量回归见 `E-20260726-01`；2026-10-14 本机 401 单测 + 2 UI 回归通过，见 `E-20261014-01` | 2026-10-14 |
| HOME-01 | 首页概览与 8 槽位自定义 | `main/Home.kt`、`main/home/*`、`DiscoveryViewModel.kt`、`data/gray/*` | `Features/Home/` | P2 / APP-01、SCH-01 | 已完成 | 今日课程时间线、天气详细/紧凑模式、8 槽位去重/增删/换位、编辑工具库、已放工具过滤和账号隔离持久化完整；紧凑天气点击只进入天气，不与课程入口冲突；首页复用账号隔离的教学周缓存，网络失败不回退为第 1 周；当前周未知时不将第 1 周课程误作今日课程。 | `HomeWidgetLayoutTests`、确定性紧凑天气 UI 专项及既有双端证据全部通过，见 `E-20260726-01`；2026-10-14 本机 401 单测 + 2 UI 回归通过，见 `E-20261014-01` | 2026-10-14 |
| ACA-01 | 成绩、多学籍、GPA 与专业排名 | `main/Grade.kt`、`GradeViewModel.kt`、`data/model/Grade*` | `Features/Grades/` | P3 / AUTH-02 | 已完成 | SDK 成绩/学籍/排名、筛选/搜索与账号隔离缓存完整；教务系统返回受限的 `gradeDetail` 时只展示清理 HTML 后的服务端文本，不再跳转教评；单学籍失败不遮蔽其他学籍；缓存刷新失败新增明确提示，本轮已在授权账号模拟器完成刷新与真实内容检查，物理机回归保留 | gradeDetail-only 解析、HTML 清理、单学籍隔离和 Demo 学期回归保留；教评跳转于 2026-09-22 移除；2026-10-19 本轮维护与待验边界见 `E-20261019-01` | 2026-10-19 |
| ACA-02 | 考试查询 | `main/Exam.kt`、`ExamViewModel.kt`、`data/model/Exam.java` | `Features/Exams/` | P3 / AUTH-02 | 已完成 | 固定 SDK `/exam`、刷新、搜索、进行中/未开始/已结束、时间、考场、座号和全状态均已实现；按 Android 3.2.0 折叠已结束考试、缩短地点并重做详情卡与加载/空状态；缓存刷新失败新增明确提示，本轮已在授权账号模拟器完成刷新与真实内容检查，物理机回归保留 | 原解析修复见 `E-20260717-05`；新增显示状态与全状态 UI 复验见 `E-20260726-01`；2026-10-19 本轮维护与待验边界见 `E-20261019-01` | 2026-10-19 |
| ACA-03 | 空闲教室 | `main/FreeClassroom*.kt`、`FreeClassroomViewModel.kt` | `Features/FreeClassroom/` | P3 / AUTH-02 | 已完成 | 真实楼栋 GET 与空闲列表 POST 契约、校区/楼栋多选、节次、日期范围、查询结果和加载/空/错状态完整；页面标题、紫色查询按钮、12 间确定性结果和卡片密度与 Android 对齐 | `FreeClassroomTests` 4 项及双端正常/加载/空/错误截图在 `E-20260715-01` 通过；Commits `d8516f2`、`1c0f950` | 2026-07-15 |
| ACA-04 | 教学评价 | `main/Evaluation.kt`、`EvaluationViewModel.kt`、`EvaluationRepository.kt` | — | 不在当前 iOS 范围 | 已移除 | 首页、工具页和成绩页无入口；不包含教评模型、视图、本地预设、Token/Cookie 引导或问卷提交网络链路 | 源码与隐私数据映射静态检查；macOS/Xcode 回归待运行 | 2026-09-22 |
| CARD-01 | 校园卡余额与付款码 | `home/CampusCard.kt`、`AHURepository.kt`、`TokenManager.kt` | `Features/CampusCard/` | P4 / AUTH-02 | 待真机验证 | 首页余额静默读取；展开二维码面板自动静默读取，首次无 ADWMH Cookie 或后续过期时均使用隐藏 WebView + OCR，不弹登录页。失败状态主动重试仍只走隐藏认证；隐藏认证成功及二维码恢复后立即静默刷新余额，避免旧失败状态继续显示 `¥ --`，较早请求不得覆盖新结果；内联和全屏二维码点按强制重新取码并刷新余额；首页先预取付款码再刷新余额，慢余额请求让位且旧结果不能覆盖新状态；续期使用二维码接口验证，预取码只在内存保留 30 秒，离开页面/后台清理，显示期间按有效年龄重新获取。 | `CampusCardInteractionTests` 新增自动隐藏续期和登录后余额刷新的状态测试；二维码点击及隐藏续期阶段诊断见 `E-20260924-01`；macOS UI 复验见 CI `35901490865`，验证码取图修复见 `E-20260924-02`；首次无 Cookie 静默登录见 `E-20260924-05`（CI `35959882196` 全绿）；授权账号真机待验证；付款码优先加载及推送前本机预览见 `E-20261014-02`，410 单测 + 3 UI 全绿；2026-10-19 本轮维护与待验边界见 `E-20261019-01` | 2026-10-19 |
| PAY-01 | 校园卡充值 | `main/CardBalanceDeposit.kt`、`CardBalanceDepositViewModel.kt` | `Features/Payments/` | P5 / CARD-01、D-005 | 待真机验收 | 真实加载卡账户；银行卡按 Android `CardBalanceRequest`、`CardPayRequest` 和 ViewModel 的字段/签名规则建单、解析 `orderid`、最终提交并刷新余额。支付宝保留固定白名单小程序路径，不向剪贴板复制身份或支付信息。学校官方页面兜底已删除 | `PaymentReadOnlyDataSourceTests`、`PaymentTests`、`YCardProductionPaymentGatewayTests` 覆盖请求、固定签名向量、成功/拒绝/未知、恢复和去重；macOS CI/IPA/Archive 见 `E-20260801-02`，仅剩授权银行卡小额真机验收 | 2026-08-01 |
| PAY-02 | 浴室缴费 | `main/BathroomDeposit.kt`、`BathroomDepositViewModel.kt` | `Features/Payments/` | P5 / CARD-01、D-005 | 待真机验收 | 支持 `feeitemid=409/430` 的账户查询与 `paystep=0` 建单；解析 `orderid` 后按 Android 当前协议执行安全键盘映射，再以 `paystep=2` 提交并刷新所选浴室余额。六位原始密码只短暂位于内存并在提交/退出后清空 | URLProtocol 测试分别覆盖 409/430 完整流程、字段白名单、映射、成功与刷新；共享状态机覆盖拒绝、超时、未知、恢复和重复点击。macOS CI/IPA/Archive 见 `E-20260801-02`，仅剩授权浴室账户小额真机验收 | 2026-08-01 |
| PAY-03 | 电控缴费 | `main/ElectricityDeposit.kt`、`ElectricityDepositViewModel.kt` | `Features/Payments/` | P5 / CARD-01、D-005 | 待真机验收 | 保持 `feeitemid=488` level 0→4 级联和余额查询；按 Android 兼容签名建单，每个订单单独获取动态安全键盘材料，映射后签名提交并刷新当前房间余额。拒绝或未知结果不伪造余额刷新 | URLProtocol/固定向量测试覆盖签名、每订单动态材料、最终提交、成功刷新、拒绝、超时、未知、跨启动恢复和去重；macOS CI/IPA/Archive 见 `E-20260801-02`，仅剩授权房间小额真机验收 | 2026-08-01 |
| PAY-04 | 招商银行校园卡充值 | `main/CmbCardRecharge.kt`、`YcardApi.kt`、`PreferencesManager.kt` | `Features/Payments/CMBRechargeView.swift` | P5 / CARD-01、AUTH-02 | 待验证 | 生产功能继续以 non-persistent WebView 承载真实校方页面，内存 Cookie 和内部导航严格限制到 `ycard.ahu.edu.cn`、`epay92.ahu.edu.cn`，招商银行外跳仅允许固定目标且不得携带校园凭据。隐藏验收模式改为原生 HEAD 链：不创建 WebView、不执行 JavaScript、不加载资源、不发送请求体、不自动跟随跳转；逐跳验证精确 HTTPS 主机、入口契约及扣款前路径，失败保持粘性并安全关闭 | `PaymentAcceptanceTests`、`NewPaymentFeatureTests`、隐藏 Debug UI 专项及实时官方入口探测全部通过，最终证据见 `E-20260801-01`。Simulator/Demo 只证明状态机，仍须授权账号和物理 iPhone 证据 | 2026-08-01 |
| PAY-05 | 网费充值 | `main/NetworkRecharge.kt`、`NetworkRechargeViewModel.kt`、`YcardApi.kt` | `Features/Payments/NetworkRechargeView.swift` | P5 / AUTH-02、D-005 | 待真机验收 | 保持真实账户、套餐统计、快捷金额、服务端限额、Bearer/Cookie/Referer 与内存响应 Cookie；生产流程完成入口预热、账户查询、兼容签名建单、每订单动态安全键盘映射、最终提交和账户刷新，不再跳转学校官方页面 | `NewPaymentFeatureTests`、`YCardProductionPaymentGatewayTests` 覆盖预热/查询顺序、字段、签名、双订单动态材料隔离、成功刷新、拒绝、未知、跨启动恢复和去重；macOS CI/IPA/Archive 见 `E-20260801-02`，仅剩授权网费账户小额真机验收 | 2026-08-01 |
| INFO-01 | 校历 | `main/SchoolCalendar.kt`、`sdk/RustSDK.kt` | `Features/SchoolCalendar/` | P4 | 已完成 | 下载、缓存、缩放、PhotoKit 保存照片及权限降级完整；黑色全屏、校历居中、右下保存/退出与加载/错误态按 Android 重做 | `SchoolCalendarRepositoryTests` 5 项覆盖缓存、回退、损坏恢复与照片保存 adapter；校历 UI 见 `E-20260714-01`，最终 device/权限文案编译见 `E-20260715-04` | 2026-07-15 |
| INFO-02 | 电话本 | `main/PhoneBook.kt`、`TelDirectoryViewModel.kt`、`data/model/Tel.kt` | `Features/PhoneBook/` | P4 | 已完成 | 9 类 57 个本地条目、搜索、校区号码与拨号确认完整；重新对照 Android 3.2.0 更新后的电话条目、注释和列表顺序，不申请通讯录权限 | 既有 `PhoneBookTests` 与双端证据见 `E-20260714-01`；最新 Android 基线复验见 `E-20260726-01` | 2026-07-26 |
| INFO-03 | 天气 | `main/Weather.kt`、`WeatherViewModel.kt`、`data/weather/*` | `Features/Weather/` | P4 | 已完成 | 首入 GPS、拒绝后 IP 降级、城市搜索、实况/预报/小时/AQI/生活指数、账号隔离缓存及首页详细/紧凑卡完整；详情页始终显示 Android 3.2.0 全量信息，升级时删除已下线的旧六项隐藏偏好 | `WeatherRepositoryTests` 的旧偏好恢复、首页卡模式及确定性 UI 覆盖全部通过，见 `E-20260726-01` | 2026-07-26 |
| CONTENT-01 | 失物招领只读 | `main/LostFound.kt`、`LostFoundViewModel.kt` | `Features/LostFound/` | P4 / AUTH-02 | 待真机验证 | 自动读取真实 campus/type/list 端点时会话过期先尝试隐藏续期，失败保留缓存和重试按钮，不拉起 ADWMH 可见 WebView；只读接口接受校方 `10000` 成功码，避免把“操作成功!”当成错误；分页、筛选和详情保留 | `CampusAuthenticatedClientTests` 的静默未授权与既有失物测试在 CI `35867866032` 通过；`LostFoundTests` 的 `10000` 本地夹具已在 CI `35898534602` 通过，见 `E-20260924-01`；无感续期见 `E-20260924-05`（CI `35959882196` 全绿）；真实登录联调仍依赖 AUTH-02 真机验证 | 2026-09-24 |
| CONTENT-02 | 失物发布与删除 | 同上、`crawler/model/adwnh/*` | `Features/LostFound/Compose/` | P5 / CONTENT-01 | 已完成 | 真实发布/删除端点只在服务端确认成功后改变 UI；会话过期显示失败与手动登录入口，不因自动重试触发 WebView 或重放写请求 | 既有所有权/发布/删除单测及 UI smoke 在 CI `35867866032` 全绿；真实登录联调仍依赖 AUTH-02 真机验证 | 2026-09-23 |
| CONTENT-03 | 学习资料浏览与下载 | `main/Repository*.kt`、`RepositoryViewModel.kt`、`data/repository/*` | `Features/Repository/` | P4 | 已完成 | 六学院虚拟根、面包屑、目录缓存、GitHub/代理源、Git LFS、流式下载、SHA-256/大小校验、Markdown 阅读、系统预览/分享、下载管理及自定义设置页完整；认证头不会发往非 GitHub 域 | `StudyRepositoryServiceTests` 的路径、面包屑、LFS、下载完整性、凭据边界与 UI 覆盖全部通过，见 `E-20260726-01` | 2026-07-26 |
| PREF-01 | 设置、偏好、关于、许可证与贡献者 | `Settings.kt`、`settings/*`、`PreferencesViewModel.kt`、`LicenseViewModel.kt` | `Features/Settings/` | P1→P7 | 待真机验证 | 设置首页显示真实 App 图标和账户信息卡；登录真实账号/重新登录操作仍在首页，只有隐私开关与政策入口留在偏好设置，体验用户也可访问；Debug 页及隐藏入口已删除，贡献名单保留匿名展示名并补齐 Android `develop` 两位开发者；设置行统一轻触觉、明暗和短缩放，减弱动态效果保留非动态反馈；本轮修正偏好入口高亮越界并精简数据清理/更新文案 | 设置/体验账户 UI smoke 已更新，确认账户操作不再出现在偏好设置；CI `35901490865` 的设置 UI smoke 全绿，真机待验证；2026-10-19 本轮维护与待验边界见 `E-20261019-01`；原生入口与反馈实际模拟器复核见 `E-20261019-02` | 2026-10-19 |
| SYS-01 | WidgetKit 课表组件 | `appwidget/ScheduleAppWidget.kt`、`WidgetUpdateScheduler.kt` | Widget Extension | P6 / SCH-01 | 待真机验证 | App Group 原子共享全学期课表快照，WidgetKit 小/中/大尺寸、未登录/过期/空状态、跨周 30 分钟时间线、当前/下一节强调和点击回 App 完整；本轮修正共享容器缺失状态、统一签名共享组、组件预览和周末列，重签后列表缺失仍待设备确认 | `ScheduleWidgetSnapshotTests` 6 项含跨周推进与共享容器缺失；本轮复核未签名 IPA `35884547808` 内含 `Payload/AHUTong.app/PlugIns/AHUTongWidget.appex`，不标“开发中”；签名安装/共享数据仍待用户设备验证；2026-10-19 本轮维护与待验边界见 `E-20261019-01`；可滚动、可展开的小组件指引及大字体复核见 `E-20261019-02` | 2026-10-19 |
| SYS-02 | 课程提醒与可选 Live Activity | `notification/CourseReminder*`、`CourseLiveUpdateHelper.kt` | `Core/Notifications/`、ActivityKit Extension | P6 / SCH-01 | 已实现，部署边界待验 | UserNotifications 授权、提前 10 分钟、未来三周过滤、前台/时区变化维护；可选岛卡仅课前显示，上课即结束，课中/下课不创建，独立偏好、同课复用、当天与八小时边界保留；后台预算不足时提前结束。当前没有 APNs，强制终止后的准点清理不作保证 | 既有提醒证据见 `E-20260715-04`；最新前台系统结束状态、后台截止消失、独立偏好与部署边界见 `E-20261019-06`；Widget device 编译、IPA 扩展检查及物理机验收分别记录 | 2026-10-19 |
| SYS-03 | Siri 与快捷指令（iOS 独立增强） | 不适用 | `Core/Shortcuts/`、`Core/Models/TeachingWeekParser.swift`、首页/课表快照与付款码路由 | P6 / AUTH-02、SCH-01、CARD-01 | 已实现，本地验证通过，真机待验 | 提供打开付款码和带日期参数的文字课表查询；冷/热启动与二级页面返回；体验账户拦截付款码；无课/无数据/学期越界分别返回；账号隔离、本机查询、Asia/Shanghai 日期、可靠周次锚点和中文短语资源 | `ScheduleShortcutTests` 18 项；Xcode 27.0 / iOS 26.5 专用模拟器 406 单测和 3 专项 UI 全绿，既有主界面 UI smoke 通过；iphoneos Release 和中文动作/短语元数据检查通过，见 `E-20261019-05`；物理 iPhone 侧载发现、Siri 识别/身份验证与真实付款码保留为验收边界 | 2026-10-19 |
| OPS-01 | 灰度、诊断、隐私、CI 与发布 | `data/gray/*`、`settings/Debug.kt`、`.github/workflows/ci.yaml` | `Core/Operations/`、`.github/workflows/` | P0→P7 | 已完成 | 灰度与账号摘要、脱敏日志、隐私清单、敏感扫描、Release Archive、未签名 IPA 保留；CI 单测及三组 UI 独立运行并分别保存结果，避免整套 30 分钟超时；iOS Debug 页面和隐藏入口已删除，生产支付保护仍由应用级禁写、域名阻断和 URLProtocol/Mock 覆盖 | 既有证据见 `E-20260801-01`、`E-20260801-02`；CI `35856636143` 全绿，未签名 IPA `35857197483` 构建与校验通过；2026-10-19 本轮维护与待验边界见 `E-20261019-01` | 2026-10-19 |

2026-10-19 1.0.2 对上述矩阵的增量更新（覆盖对应旧界面描述，验证见 E-20261019-06）：

| 切片 | 本轮更新 | 状态边界 |
| --- | --- | --- |
| CARD-01 / HOME-01 | 校园码弹簧展开，二维码最高 150pt；减弱动态效果保留淡入与反馈 | 客户端实现；真实扫码仍待设备验收 |
| SCH-02 | 等宽高圆形周指示器，单双位数字同尺寸，Dynamic Type 同步放大 | 模拟器 UI 回归 |
| PREF-01 | Siri 入口移入偏好并与相邻卡片同宽同圆角；设置 Tab 返回根页；Himekawa、zirui.xu 与随机双排头像，全部昵称补齐年级；单击暂停该排并弹出系统贡献浮窗，关闭自动继续，双击 QQ | 无页面内贡献卡或“继续滚动”按钮；保留既有贡献；名单与滚动回归见 E-20261019-09，物理机轻触觉待验 |
| SYS-02 | 岛卡仅课前显示，上课结束；不保留课中/课后卡片；通知独立 | 后台预算不足会提前结束，未接入 APNs；强制终止场景待实机 |
| SYS-03 | Siri 手动开关/系统设置入口、内置付款短语与无应用名快捷指令创建引导；课表紧凑回复 | 本机数据边界保留；系统 Siri 语音识别待实机 |

2026-10-19 原生 UI / 校园码维护对矩阵的增量覆盖（E-20261019-07）：

| 切片 | 本轮更新 | 状态边界 |
| --- | --- | --- |
| APP-01 / SET-01 | 设置首页/偏好原生 Form/Toggle，Siri 行与其他行使用系统一致布局，保留账户首页与按压反馈 | 正常签名模拟器宿主及原生控件 UI 已通过，见 E-20261019-07/08 |
| SCH-02 | 课表设置原生 Toggle/工具栏，移除遮挡系统材质的实色背景；课程详情同样保留系统 sheet | iOS 26.5 已实际观察背景折射/透出并保存截图；iOS 27 无本机运行时 |
| CARD-01 / HOME-01 | 校园码双通道恢复，12 秒传输超时、失败后重新打开/显式重试、15 秒内存复用、可插值展开高度与异步位图 | 不保证校方接口持续可用；真实扫码/长期会话仍需设备验收 |
| SYS-02 | 关闭通知零网络，开启先查权限/缓存，系统开关及时反馈并防止重复提交 | 仍为本地通知，未增加 APNs |
| HOME-01 | 下拉刷新课表/周次/天气/余额及校园码；课表更新后刷新 Widget 与快捷指令快照；前台余额 30 秒刷新，课表进入/回前台按 60 秒节流 | 不后台轮询；二维码显示时优先保码；失败保留旧课表并说明 |
| SYS-01 | AppIntentConfiguration 外观选择；小/中尺寸显示后续课程，大尺寸按星期/节次覆盖周末晚课，显示地点缩写及重叠提示 | 三尺寸深浅色布局渲染通过；模拟器可找到并添加，但原生编辑面板受无 Team ID 的临时签名限制，仍待有效重签实机验证 |
| SYS-03 | iOS 26+ 显式前台执行；补充 Siri 搜索误匹配的简洁引导，保留旧动作标识和认证要求 | 用户实机 iOS 27 手动执行成功，语音被当作网络搜索；不宣称端到端 Siri 语音已修复 |
| ACADEMIC-NEW-01 | 本科培养方案：教务原始 JS 数据安全解析、档案选择、模块/子模块、课程状态、未完成筛选、学分汇总与账号隔离缓存 | 真实登录模拟器查询成功；不含研究生 GMIS，不缓存原始 HTML/student 身份资料 |
| CARD-NEW-02 | 校园卡账单分页/类型/月及全部时间筛选/金额过滤/详情；完整范围的消费总额、逐日与商户统计 | 真实查询及统计与服务端收支汇总一致；统计任一页失败不展示部分总额，未迁移 Android 高级餐次/食堂识别 |

### 8.1 全量复查收口（2026-07-15）

下表保留 2026-07-15 全量复查及后续补记的历史范围和状态；该轮证据见 `E-20260715-04`，不作为当前验收计数。当前状态以第 8 节功能矩阵和本文摘要为准。2026-07-16 原生系统 Tab Bar 修复证据单独见 `E-20260716-01`。

| 覆盖切片 | 状态 | 本轮补齐内容 | 预定自动验证 |
| --- | --- | --- | --- |
| APP-01、PREF-01、OPS-01 | 已完成 | 系统 `TabView`/`UITabBar`、UIKit 原生导航栏、双原生返回；账户信息保留设置首页，隐私与登录偏好迁入偏好设置，Debug 页面删除；更新、反馈、许可证、主题与 Dynamic Type 保留 | 原生导航与底栏见 `E-20260716-01`；本轮设置 UI smoke 与截图在 CI `35856636143` 通过 |
| AUTH-02、CONTENT-01 | 待验证 | Cookie 父域/Path/Secure/HttpOnly、响应 Cookie 持久化、401/403/登录重定向识别保留；校园服务首次及后续均前台隐藏认证，网络/5xx 不删除凭据且不弹第二登录页 | Cookie 匹配/响应/重试契约保留；隐私 v4、无 Cookie 首次认证和体验账户路径待 macOS/真机回归 |
| SCH-01、SCH-02、HOME-01 | 已完成 | 当前学期按真实日期推导、真实下学期 SDK 接口、重叠课程分栏；首页课程入口、拖放编辑、灰度门、账号隔离布局和已放工具过滤 | Semester、布局、课表 Repository/UI 回归；Rust server feature 编译 |
| ACA-01、ACA-02、ACA-03 | 已完成 | 多学籍切换、真实学期排名、账号隔离成绩/考试缓存；空闲教室默认全楼栋与日期约束 | Rust 多学籍/排名解析、Swift 成绩/考试/空教室单测与全状态 UI |
| CARD-01、INFO-01、INFO-03、CONTENT-03 | 已完成 | 校园卡缓存键改为不可逆账号摘要，二维码显示时亮度提升并恢复；天气页首次进入先请求定位、拒绝后降级 IP，首页显示开关生效；校历用 PhotoKit 真正保存照片；学习资料流式临时文件落盘与系统分享 | 账号摘要、定位优先/拒绝降级、PhotoKit adapter、现有服务契约/缓存测试、Release device 构建 |
| SYS-01、SYS-02 | 已完成 | Widget 随跨周时间线推进课程与周次；未来三周通知重排；前台/时区变化维护；ActivityKit 锁屏与灵动岛实现 | 跨周 Widget/提醒单测、Widget Extension 编译、IPA/Archive 扩展检查 |

PAY-01、PAY-02、PAY-03、PAY-05 的客户端生产链路已经闭环，不再把安全 broker 或学校官方页面作为阻塞/兜底。该轮历史摘要曾按 20 / 25、19 / 25 统计，后续标签变更未同步此处；2026-10-19 已按当前矩阵重新核对为 14 / 25，见摘要。历史 PREF-01 与 OPS-01 的 macOS CI、模拟器 UI 和设备版未签名构建均已通过。

## 9. 平台差异与已知 Android 缺口

| 项目 | Android 现状 | iOS 迁移决策 |
| --- | --- | --- |
| 教学评价 | Android 3.2.0 提供单项与预设批量评教 | 为官方和学校授权准备，当前 iOS 整体移除该切片，不保留首页/工具/成绩入口、本地预设、会话引导或提交 API |
| 首登流程 | `Setup.kt` 的登录路由已注释但仍导航，主登录当前直接进入 Home，`Info.kt` 非正常必经链路 | Root 使用单一版本化协议 gate；必要说明确认后才进入 App Shell；拒绝保持在当前页，设置中可再次查看和撤回，不翻译遗留导航 |
| 首启商业弹窗 | Android 将“商业合作”与两份必要说明同等处理，拒绝即退出 | iOS 将其作为自愿阅读的社区说明，不保存强制同意，也不阻塞核心功能 |
| 返回导航 | Android 使用 Compose 顶栏与系统返回分发 | iOS 详情页保留 Android 同款内容布局，同时恢复 `UINavigationController` 原生导航栏与系统返回按钮；不自定义转场 delegate，仅启用系统拥有的左边缘 `interactivePopGestureRecognizer`，iOS 26+ 同时启用由 UIKit 协调滚动/横向手势冲突的 `interactiveContentPopGestureRecognizer` |
| 首启声明/隐私正文 | Android 固定 SHA 的正文含“不会收集/存储”“未实现上传”等绝对陈述，与 iOS 已实现的校园请求、天气网络查询及未来真实数据处理范围不完全相符 | 对话框几何、标题、控件完全对齐；正文按 D-009 使用与实际处理一致的开发期说明，不复制失真陈述。AUTH-01 功能/UI 验收不再被阻塞，正式法律文本仍是 P7 发布门槛 |
| 首启转场残影 | Android 自动截图中活动弹窗后方可见上一层非活动弹窗的淡化残影 | 只对齐活动弹窗的内容、几何与遮罩；不复制非活动层未及时移除的转场缺陷 |
| 密码与会话 | 密码、Rust Cookie、业务数据会进入 MMKV/Rust KV；Cookie 另有持久化副本 | `CredentialStore` / `CampusSessionStore` 将密码与 Cookie 限定到 ThisDeviceOnly Keychain 并按学号隔离；Rust `persist_session=0` 明确禁止 Cookie 写入 GuiXu，初始化时先清空旧内存 Cookie 再加载 Keychain seed；GuiXu 只保存非敏感业务缓存 |
| Rust 复用 | Android 使用 `.so`、JNI 和本地 HTTP 服务 | Apple Simulator/device staticlib 已验证；C ABI 管生命周期、GuiXu 初始化及 KV 增删查清，随机 token 保护的 loopback 服务承载现有 SDK 路由，Swift 使用可注入 `URLSession`，ATS 例外仅限 localhost |
| 会话续期 | `AutoLoginInterceptor` 将登录跳转转成 401，`TokenAuthenticator` 用全局 mutex 单次重登并重试原请求 | Rust typed `campus_session_expired` 经本地 HTTP 401 进入 App 级 `SessionRefreshCoordinator`；共享 Task 只登录一次，GET/HEAD/显式只读 POST 最多重试一次，支付写 POST 不重放。细节见 `docs/session-refresh.md` |
| 网络安全 | 存在全局明文流量配置 | 默认严格 ATS；仅对经论证的本地通信做最小例外 |
| 客户端协议常量 | Android 支付链在 App 内执行签名并存在可能输出业务材料的调试日志 | 按产品确认，iOS 包含 Android 已有的客户端协议签名常量以保持生产兼容；值只位于私有支付兼容层，不在回复、日志、文档、诊断或验收记录中输出。它们不被描述为可在客户端保密的用户凭据；未来服务端化可独立演进，不阻塞当前迁移 |
| 支付生产边界 | Android 客户端直接生成/提交签名请求，浴室使用当前协议的安全键盘材料，电控/网费按订单获取动态材料；`third_party` 经 Gson 模型序列化，POST 使用 OkHttp `FormBody` | iOS 对 PAY-01、PAY-02、PAY-03、PAY-05 实现同等客户端协议；PAY-02/03/05 分业务重建 Android 字段顺序、空值与转义语义，POST 采用 OkHttp 5.1.0 兼容表单编码，并增加严格主机/路径/字段策略、临时网络会话、密码立即清理和持久化订单阶段。学校官方页兜底已删除；`--demo-session` 与 URLProtocol 只走不可支付 Mock，CI 传输层拒绝真实写请求 |
| 校园卡支付宝引导 | Android 将本地姓名/学号复制到剪贴板后跳转支付宝校园卡小程序 | iOS 保持同信息与支付方式弹窗，但只打开无账号、金额和凭据参数的固定白名单 URL，不把身份信息写入系统剪贴板；未安装时保留页面并明确提示，回到 App 后必须向服务端对账 |
| 缴费数字键盘 | Android 使用平台输入法与返回操作 | iOS 数字/电话键盘没有 Return 键；本轮为缴费表单增加系统键盘工具栏“完成”，显式收起键盘，避免确认按钮被遮挡。金额、密码与订单行为不变 |
| 支付密码与待处理订单 | Android 三类密码支付分别实现，失败/日志/恢复语义不完全一致 | iOS 使用统一状态机；六位密码仅短暂存在于提交调用栈，映射/退出后立即覆写清空。建单前以受文件保护、排除备份的原子磁盘日志保存功能与 `creating`，获得订单号后立即保存 `orderid`/功能/方式/阶段；文件和完整目录链同步失败均闭锁建单。建单结果未知时锁定为 `creationUnknown`，最终请求可能发送后锁定为 `resultUnknown`，只核验同一订单而不重复建单或重提 |
| PAY-04 扣款前验收 | Android 直接在 WebView 中执行真实页面与外跳，没有独立的零扣款证明边界 | iOS 生产 WebView 与隐藏验收分离；验收仅用临时原生 HEAD 会话手动检查每一跳的精确主机、Cookie 和扣款前路径，不创建 WebView、不执行脚本、不加载资源、不发送请求体。通过只证明到达扣款前路由，不能替代物理 iPhone 网页交互、银行授权或真实扣款证据 |
| 灰度身份 | Android 支持服务端灰度、本地 SHA-256 分桶和 Debug 覆盖 | iOS 保持相同 SHA-256 分桶向量与服务端开关；Debug 页面及手动覆盖入口已删除。请求前先哈希账号，游客不生成可跨启动跟踪的设备标识，远端失败回退本地结果 |
| 课表 | 主要功能成熟；当前时间指示线有显式 TODO | 先完成行为对齐；时间线作为独立增强项，不阻塞首个课表切片 |
| 课程数据格式 | 旧 `Course` 缓存把 weekday/周次/节次保存为字符串，新教务 Activity 使用整数和 `weekIndexes`；空 weekIndexes 的 Activity 会被丢弃 | iOS `Course` 解码同时接受字符串和整数；存在 `weekIndexes` 时以去重排序后的精确周为准，否则兼容旧起止周范围；畸形数据不触发强制转换崩溃 |
| 课表缓存隔离 | 大部分当前学期缓存带用户前缀，但 `next.schedule` 仍是共享键 | iOS 持久化协议从入口要求 `UserScopedStore`，当前/下一学期均不得绕过用户命名空间；GuiXu 物理键再做 SHA-256，数据库文件不出现学号或业务键明文；旧 UserDefaults/文件缓存只迁移一次 |
| Debug 入口 | App 卡片连续点击 8 次后进入 Debug | 按 2026-09-23 用户决策彻底删除 iOS Debug 页面和八连点入口 |
| 设置点击反馈 | Compose `clickable` 默认提供按压/波纹反馈 | 保持 Android 布局不变，SwiftUI 自定义 `ButtonStyle` 在触摸按下时提供高亮、0.985 缩放和轻触觉；减弱动态效果时只禁用缩放 |
| 电话本 | Android 使用 `ACTION_DIAL`，双校区号码先弹窗选择；号码注释来自 2025 新生手册并含 2026 年 3 月更新 | iOS 保留 9 类 57 个条目及来源说明，统一补 0551 区号；所有号码（含单号码）先由确认菜单选择，再交给系统电话应用，不申请通讯录权限 |
| 校历 | Android 下载 `openahu.org/download/xiaoli.jpg` 到应用目录，支持手势缩放并可申请权限保存相册 | iOS 校验图片签名并原子缓存，损坏缓存自动清理、刷新失败显示旧缓存；使用 1–5 倍原生手势、Quick Look 和 ShareLink，不写相册，因此无需照片权限且拒绝权限时无功能损失 |
| 学习资料 | Android 通过 GitHub Contents API 浏览 6 个学院仓库，jsDelivr/Raw 下载到外部应用目录，再以 Intent 打开 | iOS 保持同一仓库清单和分支，目录按仓库/路径缓存；文件流式下载到 Application Support、文件名哈希化，使用 Quick Look/ShareLink；公开 GitHub 限流或断网时回退已访问目录和已下载文件 |
| 失物招领 | 图片上传未实现；发布/删除可能提前提示成功；“我的帖子”只过滤当前已加载数据 | 不复制缺陷；服务端确认后更新 UI，“我的帖子”使用可靠查询/分页语义 |
| 失物认证请求 | Android 使用 AutoLoginInterceptor/TokenAuthenticator 自动带会话并处理登录跳转 | iOS 认证 Web 客户端只向校园域发送内存 Cookie，显式识别 401/403 和登录重定向；失败不伪装为空列表或成功 |
| 课表桌面组件 | Android 使用 Glance/定时更新 | iOS 使用 App Group 只读快照和 WidgetKit 时间线，支持小/中/大尺寸及深链；系统可能延迟刷新，不承诺 Android 调度时点 |
| 课程提醒 | Android 使用 AlarmManager/BootReceiver 和厂商通知能力 | iOS 使用本地 UserNotifications，按校园周次与 Asia/Shanghai 提前 10 分钟重排；尚未接入 APNs，系统可延迟投递，Live Activity 是独立可选增强，不绑定普通提醒完成 |
| 天气偏好 | 多个显示开关只改内存或未被首页读取，只有 `showOnHome` 持久化生效 | 只提供能真实生效并有测试的开关 |
| 天气定位 | Android 首次进天气页立即请求精确位置，拒绝后回退 IP；缓存区级 adcode | iOS 首屏直接使用 IP，只有用户主动点击定位才请求 When-In-Use；GPS/反向编码失败或拒绝时自动回退 IP 并提示。显示位置、温度、天气、AQI、小时和生活指数六个开关立即改变页面并持久化，不提供尚未接入首页的无效开关 |
| 天气异常数据 | 固定 Android 基线遇到小数 UV 指数时可能因整数强转抛出 `NumberFormatException` | iOS 使用兼容小数的安全解析并显示结构化错误/旧缓存，不复制崩溃 |
| 加载/空/错误缓存 | Android 部分课表、成绩和考试状态截图会继续显示已播种缓存，状态与旧数据可同时存在 | iOS 对显式 demo 状态确定性显示加载、空或错误组件；生产 cache-first 仅在安全的 stale-cache 回退场景保留旧数据，不复制含糊状态 |
| 校园卡测试二维码 | Android UI 基线使用固定 mock 二维码，生产路径从真实接口刷新 | iOS UI 测试同样只使用不可支付的确定性 fixture；生产仍读取固定 SDK 动态响应，任何测试内容不得进入真实付款码 |
| 偏好中的岛卡权限 | Android 可跳转厂商岛卡/通知增强相关系统权限 | iOS 保留同序入口和状态样式；Android 专属权限入口显示平台说明，普通通知仍使用 UserNotifications |
| 许可证 | Android 列表标有 TODO，可能不完整 | 从 iOS 实际依赖生成/维护完整清单 |
| 浴室数据源 | `SdkDataSource.getBathRooms()` 当前为空响应，部分功能走其他直连接口 | 以实际接口契约和 fixture 为准，不复制空实现 |
| APK/热更新 | Android 有完整自更新、分段下载和安装流程 | 完全排除，走 App Store/TestFlight |
| 开发期真机安装 | Android 可直接安装调试 APK | 当前无付费 Apple Developer Program 账号；GitHub Actions 生成未签名 IPA，本机以 Personal Team 完成 7 天签名和刷新，不将 Apple ID、密码、证书或描述文件上传 GitHub |
| UI 截图基线 | Android 仓内三张旧图与固定 SHA 不一致 | 旧图仅作历史辅助；Android run `29359831897` 生成 48 张，iOS 既有候选生成 54 张 1170×2532 证据。共同业务状态逐屏对照；系统原生 Tab Bar 是用户批准的平台差异，不能把自绘玻璃栏冒充系统组件 |
| 四入口底栏材质 | Android 使用 Compose 自定义浮动胶囊和静态/自定义材质 | 用户于 2026-07-16 明确要求真正的系统底栏：iOS 使用 `TabView` 生成原生 `UITabBar`，Liquid Glass 与辅助功能行为跟随系统；不再直接使用 `GlassEffectContainer`/`glassEffect` 自绘栏。入口顺序、图标、文案和选中语义不变 |
| QQ/支付宝跳转 | 依赖 Android Intent/deep link | 使用 iOS URL Scheme/Universal Link 白名单，并提供未安装时降级路径 |
| 防截屏/录屏 | Android 登录/付款码可使用窗口安全标志 | 用户于 2026-07-15 明确要求移除校园卡余额/付款码录屏遮罩；iOS 不监听 `UIScreen.capturedDidChangeNotification`，录屏和截图时保持原内容可见。测试码仅为不可支付 fixture，真实码的展示风险由产品决策接受 |
| 系统栏与安全区 | Android 显示状态栏和三键/手势导航栏 | iOS 保留系统状态栏、安全区、Dynamic Island/Home Indicator；App 内容区域的颜色、尺寸、顺序和密度仍按 Android 对齐 |

本轮原生 UI 评估：根容器的系统 TabView、开发者原生 popover、Siri 的 ShortcutsLink、支付的系统键盘/文件选择器均保留。设置首页/偏好和课表弹层已迁移。下一批可评估天气设置（现有 AndroidScreen 实色背景与自绘样式选择器）以及失物招领详情/发布/我的帖子（实色容器）；它们仍有业务布局价值，不因名称带 Android 就当作死代码删除。充值确认和未知结果恢复涉及真实写请求，优先保留清楚的业务状态，单独验收后再调整外观。

### 9.1 最新 Android master 与 iOS 1.0.2 的业务差距（2026-10-19）

对照 Android `595e63c` 的路由、HomeWidgetRegistry 和对应数据/界面实现，与 iOS `7897a54` 的真实工具入口、API、模型和视图核对。以下是源码能力盘点，不代表 Android 已经在本机运行验收；不将 Android 专属界面、API 名称或贡献者介绍误判为 iOS 已有功能。

| 能力 | Android 证据（相对 Android 子仓） | iOS 当前情况 | 建议 |
| --- | --- | --- | --- |
| 校园通知与新公告提醒 | `ui/screen/Main.kt` 的 `campus_notices`，`ui/screen/main/CampusNoticeScreen.kt`、`data/notice/*`、`notification/CampusNoticeNotifier.kt` | 没有公告聚合、未读状态或订阅。当前课程本地提醒不是公告推送；Android 聚合安徽大学/研究生院公告，也不等同全部教务通知 | P1：先只读列表/详情/未读与缓存，再设计后台更新、通知权限及 APNs 服务端边界 |
| 学习通日历、作业截止、课程进度和自建日程 | `feature/xuexiaotong/`、`data/chaoxing/`；经典版工具入口、Radiant 中为主入口 | 没有学习通会话、作业/进度或本地日程模块；贡献名单中的“学习通日历开发”不代表 iOS 已实现 | P2：独立产品切片，先只读同步/本地日程，随后提醒和 Widget |
| 培养方案/完成度 | `ui/screen/main/ProgramCompletion.kt`、`data/ProgramCompletionGateway.kt` | 本分支已接入本科完成情况、模块/课程、学分、未完成筛选与账号隔离缓存 | 真实只读查询已通过；研究生培养方案仍不支持 |
| 校园卡账单与消费统计 | Main 的 `billing` / `billing_stats`，`ui/screen/main/Billing.kt`、`BillingStats.kt` | 本分支已接入只读流水/筛选/详情、月度及选定范围的每日/商户统计 | 真实账单和统计已核对；Android 高级餐次/食堂分析尚未完整移植 |
| 电费剩余天数预测与多房间预警 | `feature/recharge/.../ElectricityDeposit.kt`、`electricity/ElectricityAlertChecker.kt` | 有余额、缴费、房间选择和历史查询相关界面；没有用电预测/剩余天数、每日预算和多房间自动预警 | P2：先补只读用电数据和预测验证；用户未提供宿舍信息，真实余额/预测仍待授权测试 |
| 研究生独立登录与课表 | `data/crawler/gmis/*`、`ui/state/PostgraduateScheduleViewModel.kt`、`AcademicFeatureAccess` | 当前课表接本科 JWXT/SDK，没有 GMIS 会话/课表/周次配置，也没有研究生功能适用性分流；成绩多学籍不是该能力 | P1/P2：若核心测试账号为研究生则提升 P1，先完成独立认证和课表契约 |
| 学生邮箱 | `ui/screen/main/StudentMailScreen.kt`、`data/mail/*` | 没有收件箱、正文、附件、联系人、草稿或发送；Android 已含读写与完整网页回退 | P3：问卷邮箱 2/25；先做只读版本，发送/删除作为独立授权功能设计 |
| 菜鸟身份码入口 | Main 的 `identity_code` 外部淘宝页面 | 没有入口；它不是校园卡付款码 | P3：评估实际用户需求，可作轻量外部跳转 |
| 网费加入首页可选工具 | HomeWidgetRegistry 的 `network_recharge` | 网费充值功能已有，小工具页可用；首页自定义列表尚不包含网费 | P2 小改：补入口映射与旧布局兼容，不能算整项网费功能缺失 |
| 自定义运行期插件 | `ui/plugin/RuntimePluginLoader.kt`、`PluginRegistry.kt`、`.ahup` | 没有动态插件容器 | 暂不直接迁移 Android 动态加载方式；先定义 iOS 扩展范围 |
| 行为预测/个性化与多套 UI 主题 | `personalization/*`、`RadiantComponentPack.kt` | 没有预测系统或 Radiant 界面；已有主题色和首页自定义 | 另行确定产品需求、数据边界；当前优先 iOS 原生体验 |
| 教学评价 | Main 的 `evaluation`、Grade 到教评路由 | 已按用户既定要求整体移除 | 保持既定决策，不自动恢复 |

校园码具体差距已在本轮修复：Android `data/crawler/PaymentQrRequest.kt` 采用学校直连、Rust HTTP 回退、再直连，单通道 12 秒预算；重新打开/强制刷新可以恢复请求，内存缓存 15 秒，后台清空。iOS 增加学校直连并保留 Rust 回退，处理 HTTP 200 的会话失效业务码；取消不启动回退、换账号拒绝旧结果；不缓存或记录真实付款码。学校失败、网络失败仍可能发生，客户端恢复不等于校方服务可用性保证。

问卷 25 人：课程表 22（88%）、校园码 20（80%）、成绩/考试 19（76%）、水电网费及教务通知各 15（60%）、“安大必…”7（28%，全称未取得）、邮箱及其他各 2（8%）。多选结果不能相加当参与人数。“安大必…”不擅自等同学习通。建议先稳定登录/校园码/课表、验证成绩考试，再公告查询与可靠提醒，其后只读账单和电费预警；邮箱排后。公告订阅与用户问卷的教务通知存在关联，但不能宣称范围完全等价。

## 10. 安全门槛

以下条件在支付或真实账号广泛测试前必须完成：

- [x] D-005 已由产品明确决定：iOS 可使用 Android 现有客户端协议签名常量保持生产兼容；常量只在一个私有兼容层中出现，其值禁止进入日志、文档、诊断和验收证据。
- [x] 登录密码进入 ThisDeviceOnly Keychain；支付六位密码不进入 Keychain 或任何持久化，只在内存中完成映射并立即清空；Token/Cookie 使用既有 Keychain 或临时支付会话边界。
- [x] 建立 Swift/Rust/GuiXu 脱敏日志和有限错误映射，禁止输出 Cookie、Token、密码、完整请求/响应体、本地路径和可识别账号信息，并有回归测试。
- [x] `AuthSession` 统一处理 Cookie、Token、刷新、并发去重和过期事件。
- [x] 默认启用 ATS，仅为必要域名或经论证的本地通信配置最小例外。
- [x] 支付状态机覆盖建单前保存、订单号立即保存、重复点击、超时、取消、第三方 App 返回、结果未知、跨启动恢复和禁止重放最终提交。
- [x] CI 和自动测试由应用级开关、支付域名阻断和 URLProtocol/Mock 三层约束禁止连接真实扣款接口。
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

### E-20261014-01：弱网启动与课表日期回归

- 基线：AIO `59e9ed1` detached；iOS 远端 main `449300f`；worktree `ios-startup-schedule-fixes`，功能分支 `codex/ios-startup-schedule-fixes`。
- 已确认缺陷：冷启动等待 `/schedule/current-week` / 续期后才退出开屏；周数解析扫描任意数字，可能把学期 ID 作为教学周；离线快照随地区设置在周日换周；删除 Debug 页面后仍保留会生效的演示开关与固定时钟；下学期日期用当前学期推算。
- 修复：本地会话就绪即开放页面，网络认证结果仍按原策略处理，且不能在退出后恢复旧用户；严格周字段解析；账号/学期隔离的周数锚点缓存；共享周一/公历/校园时区计算；旧演示与灰度偏好清理，Release 禁用演示会话；未知周次不向 Widget/体验课表/提醒发布第 1 周假数据。
- 本机工具链：Xcode 27.0（27A266a）、XcodeGen 2.46.0、iOS 26.5 iPhone 17 Pro Simulator。
- 验证：401 个单元测试、2 个 UI smoke 全部通过；关键用例覆盖请求持续挂起、退出竞态、10 月真实周日期、离线周数、账号/学期隔离、周日/跨年边界、未知日期及下学期旧响应。自动化未连接真实支付服务。
- 证据：`build/startup-schedule/Final-verified.xcresult` 和 `build/startup-schedule/final-verified-test.log`（忽略的本机产物）；最终模拟器命令使用 `ENABLE_DEBUG_DYLIB=NO` 绕过本机 Xcode 27 Debug dylib 签名错误。首轮测试 actor 隔离编译错误、一次本地签名缓存错误均已修复后重跑；不将失败候选计作验证通过。
- 设备产物：Release / iphoneos 无签名构建成功，`build/startup-schedule/AHUTong-unsigned.ipa` 为 6,771,479 bytes，SHA-256 `c5472d91aa1ca3db5b7fe647540e6d2f8ca66df597e0775ce0a59fbbf4456717`。App 与 Widget 均为 arm64、版本 1.0.0（1）、最低 iOS 17；ZIP 完整性通过，均无代码签名和 embedded.mobileprovision。日志及校验见 `device-build.log`、`ipa-verification.json` 与同目录 SHA-256 文件。
- 真机边界：未持有用户校园账号，实际教务响应与物理设备的弱网/Widget 安装仍需验收；不据此增加严格完成数。付费 Ad Hoc 分发尚未登记真实设备或生成签名包。

### E-20261014-02：付款码优先加载与本机预览

- 首页先预取二维码，返回后立即显示，再读取余额；已有慢余额请求会被取消，迟到响应不能覆盖新余额。预取与点开并发时仅发一份二维码请求，失败不自动循环登录。
- 校园卡隐藏续期使用二维码接口校验会话，余额接口变慢不会阻塞付款码。预取码不落盘，只允许短暂复用 30 秒；显示期间检查年龄重新获取，进入后台或离开首页清理并取消请求，放大付款码时保留当前显示。
- 最终本机验证：Xcode 27 / iOS 26.5 iPhone 17 Pro Simulator，410 单元测试与 3 UI smoke 全部通过。新增 9 个单测覆盖请求顺序、挂起余额、旧余额覆盖、并发、过期、后台迟到响应、失败降级及真实 API 校验路径；新增 UI smoke 验证 10 秒余额延迟期间付款码已显示且可放大。自动化只使用 Mock/URLProtocol，未连接真实支付服务。
- 推送前预览：`build/startup-schedule/card-preview-final/payment-code-before-slow-balance.png` 已导出并在本机打开检查；使用演示账户、测试二维码与固定日期，余额仍显示加载态时付款码正常显示，面板高度小于 300pt。
- 证据：`build/startup-schedule/Card-priority-final.xcresult` 与 `card-priority-final-test.log`；首轮测试清理代码的 tuple 访问编译错误已修复并重跑，失败候选不计入成功结果。此前 408 单测 + 3 UI 与随后 410 单测候选也通过，最终证据以本节全量结果为准。
- 设备构建：本机 Release / iphoneos 无签名构建通过，日志为 `build/startup-schedule/qr-priority-device-build.log`；本机预览和构建检查后推送，随后打包 `AHUTong-unsigned-qr-priority.ipa`，产物元数据及 SHA-256 记录在忽略的 `qr-ipa-verification.json` 中。
- 授权校园账号、真实网络和签名后物理 iPhone 的扫码付款仍待人工验收；模拟器演示二维码仅用于渲染与请求顺序验证。

### E-20261019-01：会话恢复与七项维护回归

- 基线：AIO `59e9ed1` detached；上游 `main` 为 `449300f`；工作区 `ios-roadmap-survey`，iOS 分支 `codex/fix/ios-maintenance-20261019` 基于 PR #3 `cc3dd5f`，本轮代码提交 `bd4335f`。PR #2 的周数解析与日期问题、七项检查详情见 [本轮维护记录](2026-10-19-maintenance-audit.md)。
- 认证：临时隐藏续期失败和续期后二次过期保留本地身份/凭据；只对明确账号密码拒绝执行清理。首次登录校验后及业务读取成功后保存最新 Cookie；切换账号不复用上一账号的校园卡 Cookie；启动校验避免嵌套自动续期。
- 查询与体验：生产 API 层的成绩/考试过期重试和解码契约通过，缓存刷新失败显示明确说明；课程提醒、Live Activity 与 Widget 共用校园时区和真实节次时间。当前为本地通知，未接入 APNs。缴费表单增加数字键盘“完成”入口，解决确认按钮被覆盖；日期 UI 用例明确设置本学期，隔离前序下学期预览偏好。
- Widget：使用统一可配置共享组；共享容器不可用时明确提示，取消互不共享的私有目录回退；组件预览不依赖登录，保留周末课程。新增包检查器并接入 IPA/Archive 工作流，验证扩展保留、Bundle ID、版本和共享权限。已用实际模拟器 App 的隔离副本验证扩展移除、错误标识/共享组和签名权限缺失能被拒绝。
- 工具链：本机 Xcode 27.0（27A266a），iOS 26.5 / iPhone 17 Pro Simulator。首轮定向测试 44 项中新增会话恢复六项全部通过，1 项旧测试的模拟 Cookie 导出不符合真实语义，修正后全量单元测试 423 项通过。首轮全量 UI 共 13 项，11 项通过，暴露键盘遮挡及下学期偏好残留两项问题；修复后 `Maintenance-ui-recheck.xcresult` 中缴费、网费及启动/课表 4 项通过。另 1 项密码纠错用例暴露 SecureField 重获焦点后的输入假设，改为重新输入完整密码后，在 `Payment-correction-recheck.xcresult` 单独复验通过。合计 5 个受影响 UI 用例完成通过复验；未把首轮完整 suite 写为全绿。
- 证据：`build/maintenance/Maintenance-full.xcresult`、`maintenance-full.log`；iPhone Release 无签名构建成功，见 `device-build.log`。最终 `AHUTong-maintenance-unsigned.ipa` 为 6,807,766 bytes，SHA-256 `d105051556949d6e3ce5dd191b0407f2e47efa24b4ed3c6e4580b94936cd58ca`；App/Widget 均为 arm64、最低 iOS 17，无代码签名和描述文件，ZIP 与 Widget 结构校验通过，见 `ipa-verification.json`。
- UI 复验日志：`maintenance-ui-recheck.log`、`payment-correction-recheck.log`；最后一项复验退出码 0。Xcode 在测试完成后收集 Simulator 诊断时报告默认工具目录找不到 `simctl`，未改变测试断言结果；结果包已保存。
- 真机边界：用户报告一两天后被要求登录、重签 IPA 后 iOS 27 添加列表没有安大通；本轮未取得授权账号或重签后设备包，真实 CAS、成绩/考场、通知投递、缴费和扩展注册仍待用户设备复验。自动测试没有真实建单或扣款，未增加严格完成数；SYS-01 因用户实测问题重新进入待真机验证。

本轮测试命令（以下将共同参数合并展示，输出分别写入上述同名 `.log`）：

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
maintenance_args=(-project AHUTong.xcodeproj -scheme AHUTong
  -destination 'platform=iOS Simulator,id=64F2DE05-3F35-4563-85C7-00378E4F42B8'
  -derivedDataPath build/maintenance/DerivedData -parallel-testing-enabled NO
  ENABLE_DEBUG_DYLIB=NO)
xcodebuild "${maintenance_args[@]}" test \
  -resultBundlePath build/maintenance/Maintenance-full.xcresult
xcodebuild "${maintenance_args[@]}" test \
  -only-testing:AHUTongUITests/AppShellUITests/testAndroidParityPaymentsAndOperations \
  -only-testing:AHUTongUITests/AppShellUITests/testNetworkRechargeAndCMBPreference \
  -only-testing:AHUTongUITests/PaymentLocalParityUITests \
  -only-testing:AHUTongUITests/StartupScheduleUITests \
  -resultBundlePath build/maintenance/Maintenance-ui-recheck.xcresult
xcodebuild "${maintenance_args[@]}" test \
  -only-testing:AHUTongUITests/PaymentLocalParityUITests \
  -resultBundlePath build/maintenance/Payment-correction-recheck.xcresult
```

### E-20261019-02：原生导航、设置反馈与简洁文案复核

- 范围：继续使用同一 AIO worktree 和 iOS 维护分支；核对原生底栏、无 Debug/玻璃入口、真实图标与账户位置、设置行反馈。本次提交修复偏好入口按压高亮越过卡片边界，精简清理/更新/隐私/充值/课前倒计时文案，删除不可达说明弹窗，小组件指引支持滚动和中/大高度。详细对照见 [维护记录](2026-10-19-maintenance-audit.md#原生导航设置入口与按压反馈复核)。
- 静态检查：根容器仍是 `TabView`，四标签定义与系统选中语义未改；无自绘底栏、`UITabBarAppearance`/兼容模式覆盖、玻璃偏好或 Debug 页面。`AppMark` 与 AppIcon 图片 SHA-256 均为 `11a68849ce885e55b0bdc5be4c61b98ebb1a331b26a89e13bb121b96758f67c8`。设置域可点击行统一反馈样式；系统对话框和工具栏按钮继续使用系统样式。
- 单元测试：`SettingsInteractionTests` 5 项通过，包括普通按压、减弱动态效果保留非动态反馈、旧偏好清理和账户偏好隔离；结果在 `build/ux-review/Settings-final.xcresult`，只以其中单元测试部分为通过证据。
- 模拟器：Xcode 27.0 / iPhone 17 Pro / iOS 26.5，使用测试账户且禁用真实缴费。新增 3 个 UI 用例分别通过：`testNativeTabsSettingsStructureAndConciseCopy`（39.336 秒，`Settings-verified.xcresult`）、`testPressFeedbackWithSystemReduceMotion`（68.022 秒，`Settings-motion-confirmed.xcresult`）、`testSettingsAndWidgetGuideRemainReachable`（19.256 秒，`Settings-accessibility.xcresult`）。验证四个原生标签的顺序与选中态、App 卡片八连点无 Debug、账户入口位置、无玻璃入口、清理/更新说明、小组件指引及可达性。
- 系统设置与视觉：通过真实系统 Settings 的“减弱动态效果”开关分别运行普通与减弱状态，并恢复本次用例进入时的值；实际长按截图 `normal-pressed-fixed.png`、`reduced-pressed-fixed.png` 确认高亮留在卡片内，减弱状态不缩放。另将 Simulator 设置为深色及 `accessibility-medium` 字体运行可达性测试，已恢复原来的 light/large。设置、偏好和小组件截图已人工检查，指引完整内容可滚动、展开，“完成”可点击。
- 可视证据：全部保留在 `build/ux-review/`；`settings-ux-settings-resting.png`、`settings-ux-preferences-top.png` 为正常界面，`settings-ux-accessible-*.png` 为深色大字体；`settings-accessibility.mp4` 为约 20 秒实际模拟器录屏，按压过程另见 `settings-feedback-fixed.mp4`。均来自实际运行，未用设计稿替代。XCTest 附件随各结果包保存。
- 失败记录：早期 UI 轮次暴露系统弹层没有独立“取消”行、系统 Settings 整行与内部开关的定位差异，以及恢复后仍停留详情页导致根 Tab 不存在等测试假设。修正定位、跨应用重新进入与根页面清理后分别复验通过；`Settings-inspection`、`Settings-final`、`Settings-verified`、`Settings-motion-final` 和 `Settings-motion-recheck` 原始结果保留，不将这些完整轮次写成全绿。
- 设备构建：本次界面修改的 Release iphoneos 无签名构建成功，见 `device-final-build.log`。新包 `AHUTong-ux-unsigned.ipa` 为 6,809,519 bytes，SHA-256 `b63c0c9b430dea729a835203793227eadabd20b256e0faa441472b392c24aa16`，Widget 包结构校验通过；`ipa-verification.json` 记录的是结构检查输出，未签名包仍需重签后以 `--require-signature` 再验。前一轮维护包及其校验和不变。
- 边界：本轮 5 项单测与 3 条 UI 是定向回归，未重跑全部 423 单测；轻触觉手感、iOS 27 外观及重签后系统组件注册仍待物理机确认。静态布局遵循既有 Android 基线，本轮未重新初始化 Android 或做新一轮双端截图对照。PREF-01、SYS-01 不提升真机验收状态，严格完成数仍为 14 / 25。

主要复验命令（共同参数沿用 E-20261019-01 的 `maintenance_args`，结果与日志位于 `build/ux-review/`）：

```bash
xcodebuild "${maintenance_args[@]}" test \
  -only-testing:AHUTongTests/SettingsInteractionTests \
  -only-testing:AHUTongUITests/SettingsExperienceUITests
# 三条 UI 的最终通过证据分属上列三个结果包，未将此首轮命令写为全绿。
xcrun simctl ui 64F2DE05-3F35-4563-85C7-00378E4F42B8 appearance dark
xcrun simctl ui 64F2DE05-3F35-4563-85C7-00378E4F42B8 content_size accessibility-medium
xcodebuild "${maintenance_args[@]}" test \
  -only-testing:AHUTongUITests/SettingsExperienceUITests/testSettingsAndWidgetGuideRemainReachable
python3 scripts/verify-widget-bundle.py build/ux-review/AHUTong-ux-unsigned.ipa
```

### E-20261019-03：Android 同款导航图标与 App 图标开屏

- 参考范围：按用户要求在既有 AIO worktree 中初始化 Android，只读固定 gitlink `6164917dede45485ef67b7437d0bc3dee7644f53`（3.2.2）；`app/src/main/java/com/ahu/ahutong/ui/screen/BottomNavBar.kt` 第 40–45 行使用 `Icons.Outlined.Home`、`TableChart`、`Build`、`Settings`，选中和未选中路径相同。该 SHA 已追加基线表，仅覆盖本轮四图标，不替换其他契约的 Android 基线。
- 实现：从 AndroidX Compose Material Icons 1.7.8 源码逐条转换路径为 24×24 SVG，作为模板资源交给原生 `TabView`；移除底栏的四个 SF Symbols 映射。容器、标签、顺序、系统 Liquid Glass 和选中反馈保持系统实现。来源 URL、源码包 SHA-256 和 Apache-2.0 文本随 App 离线打包，并加入许可证页。
- 开屏：`a.circle.fill` 改为真实 `AppMark`，保持原来的加载状态条件，不人为增加开屏时长。深浅色 `ImageRenderer` 视图渲染用于视觉检查；真实慢校验启动用例验证缓存身份仍及时进入首页，不以离屏渲染代替真实启动时序。
- 开发默认：iOS `AGENTS.md` 已记录本地开发与预览默认关闭“减弱动态效果”。普通预览用例先实际关闭 Simulator 开关；无障碍专项临时打开后也恢复关闭。最终读取 Simulator `com.apple.Accessibility.plist` 的 `ReduceMotionEnabled` 和 `ReduceMotionReduceSlideTransitionsPreference` 均为 0，记录在 `build/branding/simulator-motion.json`。生产 App 仍遵守设备无障碍设置。
- 测试：本轮工具链仍为 Xcode 27.0 / iPhone 17 Pro / iOS 26.5。`Branding-unit-recheck.xcresult` 的 6 项单元测试全部通过（App 图标深浅色渲染、四模板图标入包/尺寸、入口顺序、许可证目录与离线文本）；`Branding.xcresult` 的 3 条 UI 全部通过：原生四入口与设置（48.394 秒）、真实系统减弱动态效果与恢复（69.221 秒）、慢校验不阻塞开屏（4.389 秒）。首轮 6 项单测中 1 项发现工程生成早于新许可证下载完成，导致漏入测试包；文件齐全后重新生成 XcodeGen 工程并复验全部 6 项通过。首轮结果保留，不将完整首轮写为全绿。
- 可视证据：`build/branding/settings-ux-native-tab-1.png` 至 `-4.png` 为实际模拟器四入口截图，已核对选中/未选中的轮廓形状。最终深浅色开屏视图渲染为 `recheck-app-splash-light.png`、`recheck-app-splash-dark.png`，均已目视检查；首轮离屏暗色渲染图有图像未绘制完整的情况，保留原附件，以复验图为最终视觉证据。`native-tabs-full-motion.mp4` 为约 48 秒实际系统设置与原生四入口操作录像；不包含伪造的开屏等待。
- 设备与包：重新生成工程后的 Release iphoneos 无签名构建成功，见 `build/branding/device-final-build.log`；App 包内离线许可证文件齐全。`AHUTong-branding-unsigned.ipa` 为 6,822,733 bytes，SHA-256 `a7878f5062d84880e7d49801fcf4ce7b15c497d68a0413ac83da07904f1b2654`，Widget 结构校验通过。旧维护包和旧 UI 包均保留原文件与校验和；本轮未更新 AIO gitlink。
- 边界：未构建或修改 Android；仅对照其实际导航定义与对应矢量资源，不声称进行了新一轮整屏双端像素验收。真机业务与 iOS 27 验收边界沿用 E-20261019-01/02，严格完成数不变。

复验命令（共同参数沿用 E-20261019-01 的 `maintenance_args`）：

```bash
xcodegen generate --spec project.yml
xcodebuild "${maintenance_args[@]}" test \
  -only-testing:AHUTongTests/AppTabTests \
  -only-testing:AHUTongTests/AppBrandingTests \
  -only-testing:AHUTongTests/LicenseCatalogTests \
  -resultBundlePath build/branding/Branding-unit-recheck.xcresult
# 三条 UI 的通过结果保留在首轮 Branding.xcresult，详见上述单项结果。
python3 scripts/verify-widget-bundle.py build/branding/AHUTong-branding-unsigned.ipa
```

### E-20261019-LIVE-01：课程实时活动倒计时回归

- 基线：远端 `main` / AIO iOS gitlink `449300f`；独立 AIO worktree `.worktree/ios-live-activity-countdown`，iOS 分支 `feat/live-activity-countdown`。
- 修复 `.timer` 越过上课时间后正向计时、跨课间下课时间错误、开关关闭先联网、无课程误关偏好及只切开关才维护活动的问题。同一课程活动复用，切换课程、关闭、退出会话及清缓存清理旧活动。偏好行补齐整行点击区域。
- 锁屏/展开岛同时显示距上课和距下课；紧凑岛明确显示下课剩余时间。使用 `Text(timerInterval:pauseTime:countsDown:showsHours:)` 与时间进度条，由系统更新，不依赖每秒 App 运行。截止后停零，课程结束的 stale 状态显示“本节课程已结束”。
- 无 APNs：按打开 App、回到前台、时区变化及刷新课表维护当天课程；不承诺 App 长期不运行时自动创建/切换后续课程，staleDate 也不是准点结束 Activity 的调度器。
- 本机 Xcode 27.0（27A266a），独立 iPhone 17 Pro / iOS 26.5 Simulator；`xcodegen generate --spec project.yml`、App/Widget/测试目标编译及定向 29 单测通过，0 失败（12 项 `CourseLiveActivityTests`、9 项提醒、4 项设置、4 项体验课表）。最终结果：`build/LiveActivityUnitValidation3.xcresult`；使用 `test-without-building` 复验编译后的最终核心逻辑。
- UI：`testLiveActivityPreferenceDoesNotRequireCourseReminder` 在 `build/LiveActivityUIValidation6.xcresult` 中通过；`testCourseCountdownContinuesInBackgroundAcrossClassStart` 在 `build/LiveActivityCountdownValidation7.xcresult` 中通过。前者截图见 `build/LiveActivityUIAttachments6/`，后者四张截图见 `build/LiveActivityCountdownAttachments7/`。Widget 辅助功能标签是归档快照，倒计时 UI 测试使用系统 Vision 识别真实截图数字；不把静态辅助功能标签当作逐秒刷新证据。
- 实际后台截图：距上课 `0:37 → 0:31`，距下课 `2:07 → 2:01`；越过上课后前者保持 `0:00`，后者继续 `1:14 → 1:10`，课程进度随时间推进。无账号、无网络和无 APNs 参与此 UI fixture；fixture 仅 Debug 加显式测试启动参数可用，不提供用户 Debug 入口。
- 首轮 UI 发现 `pauseTime` 会立即暂停，已移除；测试启动/点击/辅助功能快照问题已根据截图与界面树修正，最终证据采用上述独立通过的用例。物理 iPhone 的锁屏、常亮屏刷新节奏、灵动岛和系统权限仍需真机回归。

### E-20261019-04：合并前回归修复

- PR #4 包含 #3 的精确尖端 `cc3dd5f`；#2 按用户要求暂不合并。
- 修复课表 `.task` 随 Tab 重现而无条件重置第 1 周；仅首次加载或切换学期重置，Tab 返回保留用户所选周。
- 增加 `StartupScheduleUITests.testSelectedWeekSurvivesTabReentry`，覆盖选第 2 周、切换设置、回到课表、日期保持及回到当前周。
- CI 拆为 `unit`、`ui-navigation`、`ui-services`、`ui-settings` 四个独立任务，关闭测试并行以隔离共享偏好，使用独立 iPhone 17 Pro；每组 40 分钟并分别保留 xcresult。新增 UI 类自动进入 settings 分组。
- 本机验证：独立 `AHUTong Integration 1.0.1 QA` 模拟器，Xcode 27 / iOS 26.5；425 单测 + 3 UI 全部通过，结果见 `build/integration-1.0.1/Maintenance.xcresult`；CI YAML、shell 语法和 AppShell 用例分组覆盖检查通过。不在真实账号模拟器上运行自动化。


### E-20261019-05：1.0.1 阶段功能集成与快捷指令引导（由 1.0.2 继续交付）

- 集成精确源提交：维护 PR #4 `fcd4fb9`（包含 #3 `cc3dd5f`）、实时活动 `89975b7`、快捷指令 PR #5 `5f92a1c`。其余远端历史功能分支均已被原 `main` 包含；所有其他本地 iOS worktree 已只读复核，无额外未提交功能。#2 保持未合并。
- 冲突处理：保留严格教学周解析、按账号/学期的离线周锚点、旧请求隔离、二维码优先预取与过期刷新、Android 同款原生 Tab 图标、设置反馈；快捷指令快照接入同一可靠周次和注入存储。实时活动复用校园时区和真实节次，不重新引入设备时区或时刻表副本。
- 设置首页新增“Siri 与快捷指令”入口，引导页包含两个动作、简短口令、日期选择、本机数据来源和系统 `ShortcutsLink`；统一 `CFBundleName` 为“安大通”以避免系统按钮显示工程名，支持滚动与 Dynamic Type，沿用设置按压反馈；无 Debug/玻璃开关。
- App 与 Widget 同步 `1.0.1 (2)`。本次为实机测试用未签名 IPA，不上传商店、不改变 AIO gitlink，不进行真实支付。
- 云端首轮 `39229524785` 的 457 单测通过，设置组 12 UI 中仅后台倒计时测试失败：runner 的启动/截图/OCR 耗时使 135 秒测试课程在最后一轮识别前结束，未再显示两个倒计时。保留原失败日志/附件，不将该轮写为全绿；Debug fixture 改为 90 秒后开课、10 分钟后结束，并按截图时间与识别的剩余秒数等待跨上课，保留后台递减和截止停零断言。生产调度、倒计时和 IPA 功能不变。
- 测试计时修正后，本机 `Live-timing-recheck.xcresult` 通过（后台跨上课回归）；Release 再构建成功。最终交付包 `build/integration-1.0.1/AHUTong-1.0.1-2-final-unsigned.ipa`：6,942,774 bytes，SHA-256 `186ed10e69a2218ea1fff6d3217f3c7ade41ac5192d59c75544c7ce97f471139`。之前的包与原失败证据保留。
- 最终中文系统按钮 UI 通过 `Guide-branding.xcresult` 复验，截图 `build/integration-1.0.1/shortcuts-guide.png` 已目视检查；`device-final-build.log` 为最终 Release iphoneos 构建成功证据。两项带系统身份验证的 App Intents、两个 App Shortcuts、必填日期和中文 NLU 元数据检查通过。
- 最终本机包 `build/integration-1.0.1/AHUTong-1.0.1-2-unsigned.ipa`：6,942,774 bytes；SHA-256 `793f8afa8a0fbbda3ac02bde0901e523648c46203f1ec2a7a85d32d99b13032a`；ZIP 完整性和 Widget BundleID、版本、可执行文件、共享组结构检查通过。此为未签名包，重签后仍需保留 Widget 并复验签名与 App Group。
- 本机 Xcode 27 / iOS 26.5 独立模拟器：`Integrated.xcresult` 456 单测 + 9 UI 全部通过，覆盖后台跨上课倒计时、独立偏好、付款码冷/热启动与体验拦截、设置引导、日期和 Tab 返回；`Final-recheck.xcresult` 补充校园默认时区/离线快照断言后 457 单测 + 1 设置 UI 通过；真实账号此前的成绩/考试刷新、校园卡与网费只读查询、前后台及冷启动保持登录均已检查；自然隔天过期、实际重签后的 Widget/Siri 与物理机实时活动仍需设备验收。浴室/房间余额按用户要求未测试。

### E-20261019-06：1.0.2 交互优化、Siri 引导与开发者页面

- 首页校园卡从余额到校园码使用弹簧展开及淡入，内联二维码从 138pt 增至最高 150pt，并随卡片宽度收缩；减弱动态效果使用短淡入，保留反馈。原小于 300pt 的紧凑面板边界继续有效。
- 课表周数字使用等宽高 44pt 的 `Circle`，随 Dynamic Type 同步放大；单双位数字不再改变外形。原生 `TabView` 保留，再次选择设置时重建设置根导航栈；课表所选周状态不受影响。
- “Siri 与快捷指令”移入偏好设置，提供系统 App 设置跳转、Siri 手动开关说明与原生 `ShortcutsLink`。新增“打开安大通付款”“打开安大通校园码”，保留“打开安大通付款码”。Apple 要求 App Shortcut 短语包含 applicationName，故无应用名的“打开校园码”由用户新建同名快捷指令承载，页面说明如何添加“打开付款码”动作并命名。
- 课表输出为 `2026.10.20 第7周周二`、逐门节次/课程/地点、`同步于10.19 17:26`；仍区分无数据、无课、超出学期、同步时间未知，保持账号隔离与校园时区。
- 新增 Himekawa（QQ 1705945565，贡献“iOS开发与维护”），保留全部既有贡献内容与 QQ 头像/联系 URL。每次进入随机分两排，第一排向左、第二排向右，以 12pt/s 循环；单击反馈并暂停该排，以系统原生 `popover` 显示贡献，关闭浮窗自动继续。不在页面下方插入贡献卡，也没有“继续滚动”按钮；双击与单击互斥识别，双击打开 QQ，未安装时显示号码。减弱动态效果/VoiceOver 改为手动横向浏览，VoiceOver 另有“打开 QQ”操作；离开页面与非前台暂停计时。
- 修正偏好中的 Siri 入口重复水平留白和独立 32pt 圆角，复用相邻偏好卡片的完整容器、16pt 圆角和内边距。入口卡片左右边界与相邻卡片一致，主要路径增加尺寸对齐和浮窗关闭后恢复滚动的 UI 断言。
- `Popover-polish.xcresult` 的贡献原生浮窗/双击与 Siri 卡片对齐 2 UI 通过；`Popover-row-check.xcresult` 进一步确认浮窗期间只有选中排暂停，关闭后两排恢复原方向。旧提交 `9b58d14` 云端单测为 462 Swift + 25 Rust 通过，导航组的 50ms 边缘快划未触发返回；保留该轮失败证据，调整为有限次数的明确边缘拖动，仍要求系统手势真实返回，不以点击返回按钮替代。
- 同轮服务组录屏确认校园卡 Mock 操作已提交，原 4 秒预算结束时界面仍为“支付中”，并非成功断言过时；保留服务端确认“支付成功”的断言，将持久化状态写入的等待预算改为 15 秒。支付选项菜单先等待可用/可点，选择后核对真实选中值；自动化显式禁止真实支付接口。
- 用户进一步要求岛卡只用于课前：调度拒绝课中课程，上课截止即结束活动，不显示下课倒计时、课程进度或结束卡片。前台截止任务与 ActivityKit 状态观察共同清理；后台申请有限执行时间，在预算耗尽前提前结束，避免进入课中后继续占位。`staleDate` 是内容失效边界，不冒充系统自动结束 API；目前没有 APNs，进程被强制终止后的准点移除仍属物理设备边界。普通课前通知与此偏好独立。
- 旧用例调整：Siri 入口位于设置首页、固定贡献者视觉列表、课表的“共几门课程/上次同步”长文断言已被本轮需求替代；本次用户改动也明确淘汰了“课中继续下课倒计时”的旧断言，替换为前台系统结束状态与后台截止消失测试。数据、安全与账号隔离断言保留。历史测试时间预算问题仍记录在 E-20261019-05。
- 本机 `Final.xcresult` 的 461 单测和 13 UI 通过；最新课前策略 `Preclass-recheck.xcresult` 的 462 单测、前台截止/后台消失/独立偏好测试通过。UI 首轮定位/手势假设失败保留于 `Polish.xcresult` 和 `Polish-recheck.xcresult`，未把失败轮计为通过。云端旧提交 `a9f9b8a` 的设置组倒计时定位与服务组菜单选中等待失败已保留，修正岛卡元素定位和菜单选中后置条件，最终 CI 与产物另行记录。
- 已获用户明确允许，在登录过的 iPhone 17 Pro 上保留数据和 Keychain 覆盖更新；真实会话仍有效，首页、校园码展开和偏好中的 Siri 引导已手动检查，没有执行充值、卸载、清空或在该设备运行自动化重置。
- 系统快捷指令库可发现两项动作，但 iOS 26.5 Simulator 上执行内置 App Shortcut 报 `Couldn't find AppShortcutsProvider`；Debug、关闭 debug dylib 的 Debug 对照以及 Release 均复现，AppIntents 元数据及 Provider 类型仍存在。Apple Developer Forums 的 [Simulator 报告](https://developer.apple.com/forums/tags/simulator?page=3) 记录相同系统与官方示例的失败，提示模拟器限制，尚不能据此保证物理机通过；不降低认证要求，实际 Siri/快捷指令运行仍保留为实机验收。
- 平台说明：[Apple WWDC25 短语要求](https://developer.apple.com/videos/play/wwdc2025/244/)、[快捷指令通过名称运行](https://support.apple.com/zh-cn/HT209055)、[Siri App 权限路径](https://www.apple.com/legal/privacy/data/en/ask-siri-dictation/)。App 与 Widget 统一为 1.0.2 (3)，不改变 AIO gitlink。

### E-20261019-07：原生设置、校园码恢复与最新 Android 差距

- 基线：独立 AIO worktree `android-ios-native-ui-campus-code`；iOS 从官方 main `7897a54` 建立 `codex/ios-native-ui-campus-code`，Android 只读固定 `595e63c`。不改 AIO 主工作区 gitlink，保留 PR #2 的未合并状态。
- 设置首页及偏好改为系统 Form；真实 UISwitch/Toggle 取代自绘开关和“Button 包住不可交互 Toggle”。开关先响应选择，异步期间防重复操作、显示准备状态，权限拒绝/加载失败回退；关闭提醒不访问校园网络；开启先检查系统权限，再读账号/学期隔离缓存，缺数据才请求学校。
- 课表设置使用系统 NavigationStack/工具栏/半高 sheet，支持原生 Toggle、上拉大尺寸和辅助功能大字号；课表设置与课程详情不再用不透明背景覆盖 sheet，材质由系统决定。iOS 26+ 默认 Liquid Glass，旧系统保留系统默认 sheet，无应用内材质开关。
- 校园码由学校 HTTPS 直连优先、Rust HTTP 回退、再次直连恢复；单次传输 12 秒；第一方请求仅向 `adwmh.ahu.edu.cn` 发送匹配的本机 Cookie，不跟随重定向、不使用共享 URLSession Cookie 存储，不记录/持久化付款码。Keychain 账号检查防止旧账号结果显示到新账号。业务码失效走现有 single-flight 前台续期；不修改凭据失效/支付写请求的既定规则。
- 界面区分被动预加载与用户打开：预加载失败不自动循环，重新展开则允许再次请求；强制刷新取消旧请求并拒绝迟到结果。短暂二维码内存复用改为 15 秒，后台立即失效。固定折叠/展开高度插值取代 `140 ↔ nil` 的不可见尺寸切换，位图生成移至后台任务并仅保留当前视图图片，避免每次 body 生成 CIContext 阻塞动画；减弱动态效果关闭尺寸动画，保留状态与触觉反馈。
- 清理已无调用的 `AndroidSettingRow`、`AndroidSettingButton`、`AndroidPreferenceToggle`、`ScheduleSettingPressStyle`、旧自绘开关颜色和冗余设置布局 helper；扩大引用审查后另删除旧 `FeatureLandingView`、`LoadableContentView`、`LoginProvider` 与 `AgreementDetailView`，保留实际使用的 `LoadableState` 和 `AgreementDocumentBodyView`。全生产 Swift 私有类型/方法静态引用扫描未发现额外“只定义一次”的候选，但不据此承诺全项目绝无死代码。`CampusAuthenticatedClient`、验证码/登录/OCR 客户端和旧偏好清理器均有真实调用，保留；测试夹具仍仅 Debug 启动参数可达，无隐藏调试页。
- 最新 Android 差距与后续建议列于 §9.1；原摘要的 25/25 仅属于历史固定范围，不能继续作为最新 Android 全量覆盖率。
- 验证：原生/校园码切片 476 项单测及 13 项不同 UI 用例跨分组回归通过；正常签名宿主下 Keychain 测试通过。结果包位于 `build/native-ui/final-regression.xcresult`、`notification-controls-final.xcresult` 与 `signed-unit-settings.xcresult`。Release arm64 Simulator 编译通过，按用户授权保留数据覆盖已登录 iPhone 17 Pro，真实校园码打开/刷新成功，未执行支付。
- 可视化：`build/native-ui/evidence/schedule-settings-system-glass.png` 展示 iOS 26.5 系统 sheet 的背景透出；`campus-code-expansion.mp4` 为演示二维码录像，原始帧可观察展开及收起的多个连续高度，非仅比较终态。默认减弱动态效果关闭。
- 过时测试与实际问题分别处理：原生 UISwitch 的值为 1/0，点击整行 AX 中心会点到标签，改为操作真实开关；用启动参数固定 NO 会锁住 NSArgumentDomain，改为由 UI 建立初始状态；原生 Form section 的多节点不能当作单张旧卡片比较，改比较实际 Cell 宽度。新增工具一度破坏原顺序，属于实际回归，已恢复浴室/电控在前、网费在末。首轮未签名宿主 Keychain `-34018` 属测试签名问题，未删除或跳过安全用例。

### E-20261019-08：首页刷新、Widget 外观、培养方案及只读账单

- 最新源码对照：Android 首页每 30 秒刷新余额，`onHomeEntered()` 只重读课表缓存，课表网络更新另有入口；iOS 旧版只推日期/读缓存且无统一下拉刷新。本轮补齐下拉课表/周次/天气/卡片刷新、进入/回前台 60 秒节流与前台 30 秒余额刷新；二维码展开时优先保码，后台不新增轮询。课表缓存失败回退保留，Widget/快捷指令快照随有效周次同步。
- Widget 保留原 kind，改用原生 AppIntentConfiguration，外观含跟随系统/浅色/深色。替换固定浅色底，明确高对比文本/课程底色；小中尺寸展示后续上课日的课程、节次和地点及溢出数量，大尺寸按节次对齐所有有效周课程，包含周末/晚课，重叠课程合并标示。共享既有 ScheduleTextFormatter 地点缩写，保证教室号优先可见，VoiceOver 保留完整地点。
- 已在系统列表找到并添加课表 Widget，布局由三尺寸 × 深浅色的真实 SwiftUI ImageRenderer 渲染截图验证。原生“编辑小组件”面板在本机临时签名 Simulator 停留加载，linkd 日志报告无法取得 Widget Team ID；不把渲染图当作原生配置 UI 已通过。打包脚本新增 App/Widget 的动作及三种外观元数据检查；重签验证还要求双方 Team ID 一致、保留 App Group/配置描述文件授权。最终仍需有效签名的 iOS 27 实机验收，不虚构签名团队绕过系统。
- Siri：用户确认实机 iOS 27 在快捷指令 App 内运行成功、解锁语音却转为网络搜索，因此将其定位为调用匹配问题，不归因于校园码网络请求。iOS 26+ 用 supportedModes 明确前台执行，旧系统保留 openAppWhenRun；未降低认证要求、未改变动作标识。引导保留带安大通的短语，补充运行自建快捷指令/改为独特名称的建议。Apple 要求 App Shortcut 触发短语包含 applicationName；无应用名的“打开校园码”仍依赖用户自建快捷指令及 Siri 匹配，不承诺应用可以强制 Siri 命中。参考 [Apple App Intents](https://developer.apple.com/videos/play/wwdc2025/244/) 与 [Siri 运行快捷指令](https://support.apple.com/guide/shortcuts/apd07c25bb38/ios)。
- 培养方案：复用成绩学籍与教务认证，只访问本科完成情况页；手动同域入口跳转限定精确 info/id，不转发 Cookie 到外部域名；单引号、裸枚举键、转义及 undefined 纯解析，不执行学校脚本。汇总沿用教务服务端学分，不累加课程重算学分；无服务端进度时以“学分完成率”明确展示已完成/要求学分比值。支持模块/子模块、课程状态、只看未完成、档案选择、按账号缓存与手动刷新，错误时保留旧数据。原始 HTML 与 student 身份资料不持久化。已登录模拟器读取真实方案及模块成功。
- 校园卡账单：复用 YCardReadOnlyClient 的内存 Token/Cookie、HTTP/业务 401 单次续期及严格读请求白名单，增加 GET turnover 与 count；金额用整数分，方向按 typeFrom，不以正负猜测。支持月份/全部时间、收入支出、已加载记录金额过滤、分页去重、详情；统计遍历所选范围全部页后计算每日/商户，任一页失败不发布部分总额，超过上限要求缩小范围。真实账户列表、服务端汇总与本地完整统计已核对一致；未创建充值订单、未执行支付、不保存真实账单截图或明细到仓库。
- 最终单测：`build/native-ui/final-unit-494.xcresult`，494 / 494 Swift 测试通过，包括缓存/账号隔离、重定向边界、分页/完整统计、首页缓存刷新、周末/重叠/晚课与布局渲染。打包验证 Python 4 / 4 通过并接入 CI。18 项不同目标 UI 用例分组通过（本轮无“18 用例单个整包”）；新增只读查询及 Siri 冷启动/跨 Tab 重复/体验账户边界见 `services-final-validation.xcresult`，原生 Form 行宽修正后的 Siri 引导见 `shortcut-native-form-final.xcresult`。地点缩写后的 Widget 渲染复验见 `widget-location-final.xcresult`。
- 构建/产物：Xcode 27.0 / iOS 26.5 Simulator，Release arm64 Simulator 和 unsigned iphoneos 均已编译；版本保持 1.0.2（3），本轮不是生产发版。产物、校验和与最终构建记录在 `build/native-ui-device/`；发布前需继续完成 iOS 27 的 Siri/Widget 有效重签物理机复验。维护 PR [#6](https://github.com/OpenAHU/AHUTong-iOS/pull/6)，云端检查状态以该 PR 为准；最终本地产物和 SHA-256 记录在同目录 verification JSON。最终可视化复查将本科说明移入列表脚注，避免底部浮层遮挡课程文字。首次云端 Xcode 26 在 Widget 的复合 VoiceOver 表达式触发类型检查超时，本机 Xcode 27 未复现；已拆为显式字符串 helper，以云端重新编译结果作为兼容性验收。

### E-20261019-09：开发者名单与年级

- 按用户要求加入 QQ `1793838025`。资料取自本轮固定 Android `595e63c` 的 `DeveloperViewModel.kt`：昵称 `zirui.xu（24级）`、贡献“功能维护、开发”。头像按 QQ 号联网加载；昵称与年级为本地显示资料，不宣称自动同步 QQ 昵称。实测 `r.qzone.qq.com` 与 `users.qzone.qq.com` 的资料接口均返回 `need login`，目前没有接入失败的自动查询。
- 保留 iOS 已指定的别名、表情与零宽字符；根据同一 Android 名单补齐 s1nk（20级）、表情昵称（21级）、原空白昵称/堂吉诃德/Yukon（22级），保留 MuxYang 和 InChange-Jiang（25级）。用户明确 Himekawa（QQ `1705945565`）为 24 级。
- 双击资料链接从仅含 `uin` 补齐 `src_type=internal`、`version=1`、`card_type=person`、`source=qrcode`，使用 URLComponents 组装。参考 [QQ 官方跳转页](https://qm.qq.com/cgi-bin/qm/qr) 中的资料页参数约定；QQ 是否实际展示指定个人资料仍需用户所用版本实机复验，`openURL` 接收成功仅代表系统交接。浮窗保持昵称、贡献及 QQ 号，按用户要求不增加复制按钮。
- 2026-10-19，iPhone 17 Pro QA / iOS 26.5，`build/native-ui/contributors-final.xcresult`：6 项单元测试、1 项 UI 测试全部通过。覆盖完整个人资料链接/头像契约、九人随机分两排无遗漏、两排独立暂停计时、新成员及 Himekawa 昵称年级、系统贡献浮窗、关闭恢复滚动与双击 QQ 的未安装反馈；默认减弱动态效果关闭。新增头像地址 HEAD 返回 HTTP 200 / image/jpeg。最终无复制按钮的界面截图位于 `build/native-ui/evidence/contributors-final/`。
- 上一提交 `96e5679` 的云端 [四组 CI](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39262041058)、[Release Archive](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39262036452) 和 [unsigned IPA](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39262036461) 已全部成功，确认 Widget 编译兼容修复在云端 Xcode 26 通过。本切片保持 1.0.2（3），用户暂缓 IPA 调试。

## 12. 风险与阻断项

| ID | 风险 | 等级 | 缓解与解除条件 | 状态 |
| --- | --- | --- | --- | --- |
| R-001 | Rust crate 的 Apple target、FFI 和依赖兼容性未知 | 高 | 固定子模块已完成 Simulator/device staticlib、C ABI 生命周期和 Swift 请求链路验证；持续由两条 macOS workflow 防回归 | 已解除 |
| R-002 | 登录依赖多个校园系统、Cookie 同步、验证码/OCR 与页面解析 | 高 | 已固化脱敏 fixture/契约，统一 AuthSession、Rust Cookie 同步、过期重登和可观测错误均通过 CI；继续用授权账号监测外部页面变化 | 已缓解 |
| R-003 | 客户端协议常量与敏感日志风险 | 严重 | 产品已批准客户端兼容方案；协议常量集中在唯一私有类型，源码/Archive 检查其隔离位置，Swift/Rust/GuiXu 禁止输出密码、映射、签名和完整请求体。未来轮换或服务端化属于独立加固，不再阻塞当前迁移 | 已按产品决策缓解，不阻塞实现 |
| R-004 | 支付缺少稳定沙箱，真实验证可能涉及资金 | 严重 | 自动测试全部使用 URLProtocol/Mock 并从传输层禁止真实写请求；PAY-01、PAY-02、PAY-03、PAY-05 只由用户在授权账号/房间和最小金额下手动验收，未知结果锁定原订单且不得重提 | 仅阻塞真机验收，不阻塞实现 |
| R-005 | 早期 Windows 环境不能运行 Xcode | 高 | 当前已使用本机 macOS/Xcode 27.0 验证，见 E-20261019-01；iOS 27 与授权账号真机回归仍待完成 | 本机限制已解除，真机边界保留 |
| R-006 | 历史 Android 截图与固定 SHA 不一致，且原环境无 Android Emulator 基线 | 高 | 已建立固定 SHA 的 Android CI/UI pipeline，并与 iPhone 13 Pro Simulator 按 1170×2532、43 个同状态画面完成逐屏终验 | 已解除 |
| R-007 | 核心 Android 业务缺少自动化测试 | 高 | iOS 迁移先补 fixture、解析、周次、会话和支付状态机测试 | 开放 |
| R-008 | 外部校园页面、第三方 API 与 App Store 政策可能变化 | 高 | 域隔离、契约监控、失败降级、隐私/审核复查；HEAD 不受支持或页面路由变化时必须安全失败，不允许退回 WebView 脚本守卫冒充无扣款证据 | 开放 |

## 13. 当前维护与历史工作包

2026-10-19 起按用户确认的七项顺序执行，见 [本轮维护记录](2026-10-19-maintenance-audit.md) 与 [维护计划](2026-10-19-ios-maintenance-plan.md)。以下 UI-W1、P2-P6-W1、P5-P7-W2 和 P0 工作包保留为历史迁移记录；其中旧 Debug 隐藏入口、安装包和导航决策已被后续记录覆盖，不作为当前操作步骤。

### UI-W1：既有迁移页面严格复验

- [x] 将固定 Android SHA 的 Compose 渲染设为唯一视觉真源，并让规则追溯覆盖 6 个既有完成切片。
- [x] 建立 Android 对齐色板、页面、卡片、标题、搜索、底栏等 SwiftUI 共享组件。
- [x] 重做首启协议、主页、课表、工具、设置、电话本、校历、天气和学习资料页面。
- [x] 移除系统 `TabView`/默认列表外观残留，修复安全区透明、截图切换态和滚动层遮挡。
- [x] 在 macOS CI 通过 87 个单元测试、3 条完整 UI 路径，并导出 43 张 1170×2532 iPhone 13 Pro 截图。
- [x] 在固定 Android SHA 上采集 43 张同尺寸、同数据状态截图；仓内三入口旧图未被作为证据。
- [x] 对正常、加载、空、错误、弹窗、详情、二维码和偏好状态完成 Android ↔ iOS 对照，未说明差异清零。
- [ ] 在 iPhone 13 Pro 上安装 `AHUTong-unsigned-ipa-46` 的本地 7 天签名版本，验证安全区、字号、触控、拨号、缩放、定位、通知、Widget、Quick Look/分享。
- [x] D-009 已批准开发期首启语义；正式法律文本转入 P7，不再阻塞 AUTH-01 功能完成。

### P2-P6-W1：80% 功能收口

- [x] AUTH-02 完成登录、Keychain/Cookie 会话恢复、过期重登、无凭据清理与退出闭环。
- [x] SCH-01 完成真实课表/当前周数据源、离线缓存、Widget 快照与提醒联动。
- [x] ACA-03 完成空闲教室真实契约、多条件查询、全状态测试和双端 UI 终验。
- [x] CONTENT-01 完成认证只读列表、筛选、分页、详情和图片降级。
- [x] CONTENT-02 完成发布/删除服务端确认、所有权校验、“我的帖子”和发布面板。
- [x] SYS-01 完成 WidgetKit Extension、小/中/大尺寸、状态、时间线和深链。
- [x] SYS-02 完成普通课程提醒授权、提前量、本周/时区过滤、替换和关闭清理。
- [ ] 使用授权校园账号和物理 iPhone 13 Pro 回归真实外部服务、通知投递与桌面 Widget；此项不冒充 Simulator 证据。

### P5-P7-W2：100% 收口与真机验收

- [x] PAY-01、PAY-02、PAY-03、PAY-05 完成统一金额校验与订单阶段状态机；建单前保存 `creating`，拿到订单号后立即保存 `orderid`/功能/方式，建单结果未知时禁止再建单，最终请求可能发出后只核验同一订单而不重放。
- [x] PAY-01～03 的真实只读账户链已接入 Android 对应契约，具备加载、空、错误、重试和过期请求隔离；缺失余额不伪造为 0。
- [x] PAY-01 银行卡客户端签名/建单/最终提交/余额刷新与支付宝小程序路径已实现；学校官方页面兜底已删除。
- [x] PAY-02 支持 409/430 建单、安全键盘映射、最终提交与余额刷新；PAY-03/PAY-05 支持每订单动态材料、兼容签名、最终提交与余额刷新。
- [x] 六位密码只短暂位于内存，映射或退出后立即清空；不写日志、不持久化、不进入剪贴板。Demo 状态不得进入生产。
- [x] PAY-04 隐藏验收已改为原生 HEAD、手动重定向、精确主机/路径、无请求体/无 WebView/无脚本/无资源加载。
- [x] 通用学校官方页面及无凭据入口探测已删除；隐藏 Debug 只保留独立 PAY-04 招行扣款前 HEAD 验收。
- [x] OPS-01 完成 Android 同算法灰度、Debug 诊断、账号摘要、脱敏日志、隐私清单、数据地图、敏感信息扫描、Release Archive 和 Personal Team 发布手册。
- [x] GitHub Actions 生成含 Widget 与双隐私清单的未签名 IPA/Archive；仓库和产物不含签名证书、描述文件或 Apple ID。
- [x] URLProtocol/Mock 自动测试覆盖四条生产请求字段、签名固定向量、安全键盘映射、成功、拒绝、超时、未知状态、恢复和重复点击；自动测试禁止真实扣款。
- [ ] 按 `payment-device-acceptance.md` 在物理 iPhone 13 Pro 使用授权账号手动完成 PAY-01～05 的脱敏小额验收。
- [x] 原生 Tab Bar 的 APP-01 已由 `E-20260716-01` 恢复“已完成”；PAY-01～05 只有取得真机证据后才从“待真机验收”推进到“已完成”，不以 Mock 或未扣款 UI 伪造严格 100%。
- [x] 液态玻璃偏好入口删除已通过 `E-20260716-02` 最终 CI，PREF-01 恢复“已完成”；设置中不得重新加入可关闭系统 Tab Bar 材质的开关。
- [x] 设置首页 `Debug` 可见行已按 `E-20260717-02` 删除；完整诊断页只允许由 App 信息卡 8 连点隐藏入口进入。
- [x] 设置域可点击项已按 `E-20260717-03` 统一提供即时按压和触觉反馈，并覆盖减弱动态效果语义。
- [x] 课表主体已按 `E-20260717-04` 恢复 1～20 周原生左右分页，并完成真实双向滑动、课程卡导航和辅助功能回归。
- [x] 考场查询已按 `E-20260717-05` 修复 Rust 当前 HTML 解析崩溃，并覆盖座位号/空字段解码和考试卡 UI 回归。
- [x] 总览课表与下学期预览已按 `E-20260717-06` 恢复可靠整行交互、Android 同时间槽分组和真实下一学期 ID 解析。

### P0-W1：工程与契约起点

- [x] 为 D-001 记录可替换的临时工程值。
- [ ] 确认 D-002 许可证、最终 Bundle ID 与签名团队。
- [x] 新增 iOS 子仓 `AGENTS.md`、`.gitignore` 和基础 README。
- [x] 创建 SwiftUI App、Unit Test、UI Test Targets 和四入口空壳。
- [x] 建立 `Core/Networking`、`Core/Auth`、`Core/Persistence` 的协议边界与测试替身。
- [x] 为 User、Course 和统一错误建立第一批模型与脱敏 inline fixtures。
- [x] 建立版本化首启协议 gate、拒绝/撤回/再次查看路径和 UI smoke。
- [x] 建立 Keychain SecureStore/CredentialStore，并以非生产 fixture 验证增删查和账号隔离。
- [x] 建立课表 cache-first/refresh/stale-cache Repository 与 SHA-256 文件缓存。
- [x] 配置 macOS 26 CI，并动态选择可用 iOS Simulator。
- [x] 配置手动未签名 IPA workflow，供本机 Personal Team 7 天签名安装。
- [x] 运行首次 macOS build/test，并把 Xcode、Simulator 与结果证据回写 APP-01。
- [x] 运行首次未签名 IPA 构建并上传 Artifact。
- [ ] 在 iPhone 13 Pro 上完成 Personal Team 安装/启动验证。

### P0-W2：Rust 与登录可行性 spike

- [x] 按 AIO 规范仅初始化任务需要的 `sdk`、`GuiXu-Rust` 浅子模块。
- [x] 验证 Apple device 与 Simulator target，产出并链接对应 staticlib。
- [x] 对 login/schedule/cookies 完成 C ABI 生命周期 + token loopback + Swift `URLSession` 最小闭环。
- [x] SDK `e826156` 补齐 Apple GuiXu 初始化、KV 增删查清、结构化错误/panic 边界；Swift 接入账号隔离、物理键哈希、旧缓存一次迁移和清缓存闭环。
- [x] iOS Cookie 保持 ThisDeviceOnly Keychain 单一持久化来源；Rust Apple 初始化使用 `persist_session=0`，并由 Rust 测试证明 Cookie 不写入 GuiXu。
- [x] 形成 D-003、D-004 的明确结论，并保留可注入 Swift 数据层与未来直连 FFI 替换边界。

## 14. 变更日志

- 2026-10-19：贡献名单新增 zirui.xu（QQ 1793838025，24级），全部既有昵称补齐 Android 对应年级，Himekawa 按用户指定标为 24级；补齐双击个人资料页链接参数，保持简洁浮窗；名单、随机滚动与原生浮窗/QQ 交互回归见 E-20261019-09。
- 2026-10-19：完成原生设置/课表系统 sheet、校园码双通道恢复与尺寸动画，清理无调用 UI；补充首页刷新、可配置高对比 Widget、本科培养方案及校园卡账单/统计，真实只读查询通过，明确 Siri 语音匹配与 Widget 重签验收边界；重新盘点 Android `595e63c`，修正全量对齐措辞（E-20261019-07/08）。

| 日期 | 条目 | 变更 | 验证证据 | Commit / PR |
| --- | --- | --- | --- | --- |
| 2026-07-14 | INIT-001 | 建立 Android → iOS 长期路线图；固定三仓基线；完成 Android 功能、架构、安全风险和 iOS 空仓现状盘点；尚未迁移功能 | 只读源码审查；Android/iOS/AIO `git status` 均在改动前干净；未初始化 Android 嵌套子模块 | — |
| 2026-07-14 | APP-001 | 建立 XcodeGen 工程基线、SwiftUI 四入口、统一页面状态、单元/UI 测试骨架及 macOS CI；APP-01 进入待验证 | Windows：`project.yml`/workflow YAML 与 asset JSON 解析通过；14 个 Swift 文件分隔符和全仓空白检查通过；当前环境无 `xcodebuild`，未执行编译 | — |
| 2026-07-14 | OPS-001 | 新增 `codex/**` 推送及手动触发的 macOS 26 未签名设备 IPA workflow，产出 IPA 与 SHA-256 并保留 7 天；明确 Personal Team 本地签名边界 | Windows：PyYAML 6.0.3 解析成功，job/产物路径断言及 `git diff --check` 通过；当前环境无 `xcodebuild`，GitHub Actions 和 iPhone 13 Pro 安装待验证 | — |
| 2026-07-14 | OPS-002 | 首次 Runner 构建因尚无 `AppIcon` 资产失败；开发期关闭占位 AppIcon 要求后，Simulator 测试、Release 真机构建、IPA 打包、校验和生成及 Artifact 上传全部成功；正式品牌资产迁移时恢复 AppIcon | 失败：Unsigned IPA `29275282513`、iOS CI `29275282471`；修复后成功：Unsigned IPA `29275491141`，Artifact `AHUTong-unsigned-ipa-2`、51,762 bytes、保留至 2026-07-20；Simulator `29275491048` 通过 | `80d9494` |
| 2026-07-14 | APP-002 | macOS 26/Xcode 26.5 首次完整验证通过，APP-01 达到完成定义 | iOS CI run `29275491048`：2 组单元测试与 1 条 UI smoke 通过；Unsigned IPA run `29275491141`：Release iphoneos 构建、打包和上传通过 | `80d9494` |
| 2026-07-14 | CORE-001 | 建立可注入 APIClient/NetworkTransport、AuthSession 状态边界、用户隔离 DataStore/JSONStore；迁移 User、Course、Semester 和当前周纯模型，并为 Android 新旧 JSON 兼容、账号隔离及日期边界补测试 | Windows：新增 Swift 文件静态检查待执行；计划由 macOS CI 运行累计 17 个单元测试和 1 条 UI smoke | — |
| 2026-07-14 | CORE-002 | CORE-001 完成 macOS 编译测试验证；AUTH-02、SCH-01 保持实现中，下一步接 Keychain、真实 Schedule Repository 和磁盘缓存 | iOS CI `29277758473`：macOS 26/Xcode 26.5、iOS 26.4 Simulator、17 个单元测试及 1 条 UI smoke 通过；Unsigned IPA `29277758474`：Release iphoneos 编译、打包、校验和及上传通过，Artifact `AHUTong-unsigned-ipa-3`、64,576 bytes、保留至 2026-07-20 | `6b776b4` |
| 2026-07-14 | AUTH-003 | 实现版本化首启协议 gate：免责声明/隐私说明必要确认、社区说明自愿阅读、拒绝不落盘、设置内再次查看与撤回 | Windows：协议状态/导航/UI 标识静态检查待执行；3 个新增状态测试和更新后的 UI smoke 待 macOS CI | — |
| 2026-07-14 | AUTH-004 | 实现 Security.framework Keychain adapter 与按学号隔离的 CredentialStore；拒绝空凭据，支持显式删除 | Windows：敏感材料审计待执行；4 个凭据测试（含 Simulator Keychain 非生产 fixture）待 macOS CI | — |
| 2026-07-14 | SCH-002 | 实现 cache-first/refresh/stale-cache ScheduleRepository、SHA-256 文件键和原子磁盘缓存；损坏缓存自动清理，账号之间不可回退复用 | Windows：文件结构与并发边界静态检查待执行；5 个 Repository/FileDataStore 测试待 macOS CI | — |
| 2026-07-14 | OPS-003 | 首轮多目标 CI 中 28/29 个单元测试及首启 UI smoke 通过；真实 Keychain fixture 因 Simulator 测试宿主被显式禁用签名而返回 `errSecMissingEntitlement (-34018)`；移除 Simulator CI 的禁签名覆盖以使用无需开发者账号的本地 ad-hoc 签名，设备 IPA 仍保持未签名 | iOS CI `29278831447`：仅 Keychain adapter runtime test 失败，其他协议/凭据/文件/Repository 测试和“拒绝→确认→四入口”UI smoke 通过；Unsigned IPA `29278831072` 通过 | `0abca32`（首轮） |
| 2026-07-14 | AUTH-005 | AUTH-01 达到完成定义；Keychain/CredentialStore 作为 AUTH-02 安全基础通过真实 Simulator 验证 | iOS CI `29279242413`：协议 3 测试、凭据 4 测试（含 Security.framework Keychain）及“拒绝→确认→四入口”UI smoke 通过 | `0abca32`、`c1a1630` |
| 2026-07-14 | SCH-003 | SCH-01 的本地优先 Repository 与磁盘缓存子目标完成验证，真实远端适配仍待实现 | iOS CI `29279242413`：Repository 3 测试、FileDataStore 2 测试通过；总计 29 个单元测试及 1 条 UI smoke 全部通过 | `0abca32`、`c1a1630` |
| 2026-07-14 | OPS-004 | Simulator CI 改用无需 Apple 开发者账号的本地 ad-hoc 签名后，Keychain runtime test 与全套测试通过；设备 IPA 保持未签名 | iOS CI `29279242413` 成功；Unsigned IPA `29279242104` 成功，Artifact `AHUTong-unsigned-ipa-5`、150,911 bytes、保留至 2026-07-20 | `c1a1630` |
| 2026-07-14 | INFO-001 | 迁移校历真实下载、文件签名校验/缓存/损坏恢复、离线回退、缩放、Quick Look/分享和刷新错误态；INFO-01 已完成 | 公开图片端点 GET 200；CI `29281652468`：4/4 校历测试及三页面 UI smoke 通过；IPA `29281652571` 通过 | `6a84c55`、`45ef3e7`、`f1ac99d` |
| 2026-07-14 | INFO-002 | 迁移 9 类 57 个校园电话条目、分类/全文搜索、双校区号码、0551 规范化、拨号确认和来源说明；INFO-02 已完成 | CI `29281652468`：4/4 电话本测试及三页面 UI smoke 通过；IPA `29281652571` 通过 | `6a84c55`、`45ef3e7`、`f1ac99d` |
| 2026-07-14 | CONTENT-001 | 迁移 6 个公开学习资料仓库的目录浏览/缓存、离线回退、流式进度、双源下载、Quick Look/分享、单删/批删；CONTENT-03 已完成 | 六个 GitHub Contents 端点 GET 200；CI `29281652468`：6/6 资料测试及三页面 UI smoke 通过；IPA `29281652571`、Artifact `AHUTong-unsigned-ipa-8` 通过 | `6a84c55`、`45ef3e7`、`f1ac99d` |
| 2026-07-14 | OPS-005 | 三个 P4 切片完成 Swift 6 严格并发、Simulator 全量回归和 Release iphoneos 打包；用户/平台功能完成数由 2 增至 5 | macOS 26/Xcode 26.5（17F42）、iPhone 17 Pro iOS 26.4.1 Simulator：43 个单元测试 + 1 条 UI smoke 全通过；Unsigned IPA run `29281652571` 成功，425,569 bytes | `f1ac99d` |
| 2026-07-14 | INFO-003 | 迁移天气真实 API、IP/GPS/城市三种查询、权限降级、查询隔离缓存、完整天气信息和真正生效的显示设置；INFO-03 已完成 | 合肥城市查询和 IP 查询均 GET 200 JSON；CI `29296066142`：macOS 26/Xcode 26.5（17F42）、iPhone 17 Pro iOS 26.4.1 Simulator，6/6 天气测试、累计 49 个单元测试及四页面 UI smoke 全通过；IPA `29296066128` 成功 | `8186920`、`de7ba4a`、`8603887` |
| 2026-07-14 | CONTENT-002 | 验证失物招领只读端点的认证边界，确认 CONTENT-01 不能在 AUTH-02 前独立闭环并标记阻塞 | 匿名 GET `/lostfound/campus/all`、`/lostfound/type/all`、`/lostfound/all` 均返回 302 到登录页；Android 同时配置 AutoLoginInterceptor/TokenAuthenticator | — |
| 2026-07-14 | OPS-006 | INFO-03 完成 Swift 6 严格并发、Simulator 全量回归和 Release iphoneos 打包；用户/平台功能完成数由 5 增至 6 | CI `29296066142` 通过 49 个单元测试及 1 条 UI smoke；Unsigned IPA run `29296066128` 成功，Artifact `AHUTong-unsigned-ipa-11`、604,066 bytes | `8603887` |
| 2026-07-14 | UI-001 | 产品要求改为与固定 Android SHA 的实际渲染完全一致；新增追溯生效的 UI 硬约束、逐状态/逐屏截图门槛和系统差异边界，原 6 个已完成功能切片重开 UI 验收 | 路线图规则审计：原“不逐像素复刻”条款已移除；APP-01、AUTH-01、INFO-01/02/03、CONTENT-03 已重开 UI 验收 | `53cde3a` |
| 2026-07-14 | UI-002 | 新增 Android 对齐设计系统；重做首启协议、主页、课表、工具、设置、电话本、校历、天气、学习资料及四入口；移除会泄露 iOS 原生外观的 `TabView`，修复安全区透明黑底和滚动层按钮遮挡；6 个追溯切片由实现中推进到待验证 | CI `29304405649`：Xcode 26.5、iPhone 17 Pro / iOS 26.4.1，49 个单元测试 + `AppShellUITests/testAndroidParityPrimaryScreens` 通过；Artifact `AHUTong-ui-parity-xcresult-18` 含 12 张 1206×2622 PNG，逐张目视确认无原生底栏残影/黑底/空按钮；Unsigned IPA `29304405661` 成功。固定 Android SHA 同尺寸截图及 iPhone 13 Pro 仍待验证，因此完成数保持 0 | `d15a207`、`aa9cb3a`、`430bd45`、`ab3c9f6`、`3682aab`、`c40eb24`、`9d5e627` |
| 2026-07-14 | CORE-003 | iOS 新增固定 `AHUTong-sdk` / `GuiXu` 子模块、Xcode 预构建 staticlib、受 token 保护的 localhost 客户端和 Swift 模型边界，复用 Android 同一验证码、CAS、Cookie 与教务解析实现 | Windows host `cargo rustc --features server --release -- --crate-type staticlib` 成功；iOS device/Simulator target 待 macOS CI | — |
| 2026-07-14 | AUTH-006 | 迁移 Android 登录页、登录状态、ThisDeviceOnly 凭据/Cookie、冷启动恢复与退出清理；AUTH-02 进入待验证 | 新增 2 条登录持久化/退出测试；真实 SDK 登录与 macOS CI 待运行 | — |
| 2026-07-14 | SCH-004 | 接入真实 SDK 课表/当前周，完成 20 周课表、课程卡、总览、刷新、加载/空/错态和课程详情；SCH-01、SCH-02 进入待验证 | 原 5 条数据/缓存测试保留；课程详情加入第 13 屏 UI 回归；macOS CI 待运行 | — |
| 2026-07-14 | HOME-002 | 完成真实今日课程、天气与 Android 同注册表的 8 槽位首页编辑器；HOME-01 进入待验证 | 新增 2 条布局归一化、增删和换位测试；首页 UI 回归待运行 | — |
| 2026-07-14 | ACA-001 | 通过固定 SDK `/grade` 完成成绩/GPA/排名/学籍摘要、学期筛选与搜索；ACA-01 进入待验证 | 新增 2 条嵌套响应契约测试；第 14 屏 UI 回归待运行 | — |
| 2026-07-14 | ACA-002 | 通过固定 SDK `/exam` 完成考试状态、时间、考场、座号、搜索及全状态 UI；ACA-02 进入待验证 | 固定 SDK 双解析路径复用；第 15 屏 UI 回归待运行 | — |
| 2026-07-14 | PREF-002 | 设置页接入账号、退出、清缓存、主题/材质/课表/通知偏好、协议、许可证和贡献者来源；PREF-01 进入待验证 | 第 16 屏 UI 回归与 macOS CI 待运行 | — |
| 2026-07-14 | SYS-001 | 使用 UserNotifications 实现授权、提前 10 分钟、本周过滤、时区计算与刷新重排；SYS-02 进入待验证 | 新增 2 条提醒规划测试；Simulator 权限验证待运行 | — |
| 2026-07-14 | UI-003 | APP-01 完成四入口、共享 Android 设计系统及正常/加载/空/错误统一状态的双端视觉终验，状态由待验证推进为已完成 | `AppTabTests` 2 项、`LoadableStateTests` 3 项、最终 CI/IPA 和 29 屏证据见 `E-20260714-01` | `6561f25` |
| 2026-07-14 | AUTH-007 | AUTH-01 完成三份首启说明、拒绝/继续/持久化路径及 Android 活动弹窗视觉终验；Android 非活动层残影作为已知缺陷不复制 | `AgreementConsentStoreTests` 3 项、双端首启三屏和最终 CI 见 `E-20260714-01` | `6561f25` |
| 2026-07-14 | SCH-005 | SCH-02 完成 20 周课表、真实日期、单双周卡片、刷新、总览、课程详情及三种数据状态终验 | 课表/周次/模型/缓存 12 项测试；正常、详情、加载、空、错误双端截图见 `E-20260714-01` | `c634652`、`6561f25` |
| 2026-07-14 | HOME-003 | HOME-01 完成 Android 十工具/八槽位首页、今日课程进行中/下一节/结束逻辑和四种页面状态终验 | `HomeWidgetLayoutTests` 5 项；首页正常、加载、空、错误双端截图见 `E-20260714-01` | `f23f130`、`6561f25` |
| 2026-07-14 | ACA-003 | ACA-01 完成成绩解析、学籍/GPA/排名、筛选/搜索及正常/加载/空/错误 UI 终验 | `CampusGradeParserTests` 2 项及四状态双端截图见 `E-20260714-01` | `9e605b6`、`6561f25` |
| 2026-07-14 | ACA-004 | ACA-02 完成考试解析、搜索、状态排序和确定性时钟；修复 Runner 实际日期导致的 Android 基线状态错位 | `CampusExamDisplayStatusTests` 2 项；最终首卡“操作系统 / 进行中 / 09:40~11:20”及四状态证据见 `E-20260714-01` | `ffe9887`、`6561f25` |
| 2026-07-14 | CARD-001 | CARD-01 完成余额入口、动态付款码、刷新/关闭、录屏遮罩和凭据失败路径；测试二维码与生产数据严格隔离 | `CampusCardResponseParserTests` 3 项及双端付款码截图见 `E-20260714-01` | `85959a6`、`7907702`、`6561f25` |
| 2026-07-14 | INFO-004 | INFO-01 完成校历缓存、损坏恢复、缩放、Quick Look/分享和 Android 全屏布局终验 | `SchoolCalendarRepositoryTests` 4 项及双端校历截图见 `E-20260714-01` | `6a84c55`、`6561f25` |
| 2026-07-14 | INFO-005 | INFO-02 完成 9 类 57 个电话、搜索、校区选择、安全拨号 URL 和 Android 列表密度终验 | `PhoneBookTests` 4 项及双端电话本截图见 `E-20260714-01` | `6a84c55`、`6561f25` |
| 2026-07-14 | INFO-006 | INFO-03 完成 IP/GPS/城市天气、缓存隔离、显示偏好、定位拒绝降级和 Android 卡片布局终验 | `WeatherRepositoryTests` 6 项及双端天气截图见 `E-20260714-01` | `8186920`、`6561f25` |
| 2026-07-14 | CONTENT-003 | CONTENT-03 完成六仓目录、缓存、双源下载、进度、预览/分享和删除管理的 UI 终验 | `StudyRepositoryServiceTests` 6 项及双端资料页截图见 `E-20260714-01` | `6a84c55`、`6561f25` |
| 2026-07-14 | PREF-003 | PREF-01 完成设置首页及通知、通知增强、流体材质、主题色四块偏好 UI；默认紫色/绿色开关与 Android 基线一致 | `AndroidThemeColorTests` 3 项及双端设置/偏好截图见 `E-20260714-01` | `85959a6`、`c96a856`、`6561f25` |
| 2026-07-14 | OPS-007 | 最终固定 Android 和 iOS 证据链全部通过；严格完成数从 0 增至 12 / 23（52.2%），达到本轮至少 50% 目标 | Android CI `29327068093`、UI `29327068134`；iOS CI `29331379333`、IPA `29331379344`；双端各 29 张 1170×2532 PNG，iOS 68 单测 + 2 UI 测试 | Android `b063581`；iOS `6561f25` |
| 2026-07-15 | AUTH-008 | AUTH-02 完成验证码/CAS/Cookie 接入、ThisDeviceOnly Keychain、冷启动恢复、过期凭据重登、无凭据清理与退出闭环 | `CampusSessionStoreTests` 4 项、`CredentialStoreTests` 4 项、登录正常/工作中/错误状态及最终 CI 见 `E-20260715-01` | `d8516f2`、`77a5ae5` |
| 2026-07-15 | SCH-006 | SCH-01 完成真实课表/当前周请求、cache-first/refresh/stale-cache、账号隔离，并向 Widget 和提醒输出统一数据 | 课表 Repository、文件缓存、周次和模型共 12 项测试及课表全状态回归见 `E-20260715-01` | `d8516f2` |
| 2026-07-15 | ACA-005 | ACA-03 完成真实楼栋/空闲教室契约、多楼栋与节次/日期查询、12 间结果和加载/空/错误状态 | `FreeClassroomTests` 4 项及双端空闲教室 4 状态截图见 `E-20260715-01` | `d8516f2`、`1c0f950` |
| 2026-07-15 | CONTENT-004 | CONTENT-01 解除认证阻塞，完成带 Rust Cookie 的失物/寻物列表、筛选、分页、详情和图片降级 | `LostFoundTests` 只读 3 项及双端列表/详情/三态截图见 `E-20260715-01` | `d8516f2`、`7b688b7`、`aeda622`、`1c0f950` |
| 2026-07-15 | CONTENT-005 | CONTENT-02 完成字段校验、发布/删除服务端确认、所有权保护、“我的帖子”和 60% 发布面板 | `LostFoundTests` 写操作 3 项及双端发布面板截图见 `E-20260715-01` | `d8516f2`、`aeda622`、`77a5ae5` |
| 2026-07-15 | SYS-002 | SYS-01 完成共享课表快照、WidgetKit 小/中/大尺寸、会话/空状态、30 分钟时间线和深链 | `ScheduleWidgetSnapshotTests` 4 项、Widget 预览及 IPA 扩展检查见 `E-20260715-01` | `d8516f2`、`d30f8e3` |
| 2026-07-15 | SYS-003 | SYS-02 完成 UserNotifications 授权、提前 10 分钟、本周/时区过滤、托管请求替换与关闭清理；Live Activity 继续作为可选增强 | `CourseReminderPlannerTests` 5 项及提醒开启截图见 `E-20260715-01` | `d8516f2` |
| 2026-07-15 | OPS-008 | 双端 43 屏证据、iOS 87 单测 + 3 UI 测试及含 Widget Extension 的未签名 IPA 全绿；严格完成数由 12 增至 19 / 23（82.6%），达到本轮 80% 停止目标 | Android CI `29351110964`、UI `29351111083`；iOS CI `29353937788`、IPA `29353938071`；双端各 43 张 1170×2532 PNG | Android `887a0c5`；iOS `77a5ae5` |
| 2026-07-15 | PAY-001 | PAY-01 完成金额校验、统一幂等状态机、银行卡/支付宝选择、第三方返回、取消/超时/未知结果和服务端对账客户端闭环；生产默认安全拒绝扣款，因 D-005 保持阻塞 | `PaymentTests` 17 项共享通过；iOS 正常/弹窗/Mock 成功三屏及 Android 正常/弹窗见 `E-20260715-02` | `c091244` |
| 2026-07-15 | PAY-002 | PAY-02 完成浴室选择、手机号查询、金额、仅内存六位密码和服务端确认状态机；因签名网关与授权浴室账户缺失保持阻塞 | `PaymentTests` 17 项共享通过；iOS 正常/密码弹窗/Mock 成功三屏及 Android 正常屏见 `E-20260715-02` | `c091244` |
| 2026-07-15 | PAY-003 | PAY-03 完成校区→楼栋→楼层→房间级联、余额/累计充值、金额、仅内存六位密码和结果核验；因签名网关与授权电表缺失保持阻塞 | `PaymentTests` 17 项共享通过；iOS 正常/密码弹窗/Mock 成功三屏及 Android 正常屏见 `E-20260715-02` | `c091244` |
| 2026-07-15 | OPS-009 | OPS-01 完成 Android 同算法灰度、账号摘要、本地兜底/Debug 覆盖、脱敏日志、隐私清单/数据地图、敏感信息扫描、Release Archive、未签名 IPA 与 Personal Team 发布手册，严格完成数由 19 增至 20 / 23（87.0%） | `ReleaseOperationsTests` 8 项；Android CI/UI、iOS CI/IPA/Archive 及产物见 `E-20260715-02` | `c091244` |
| 2026-07-15 | UI-004 | 将四入口自绘底栏从模拟材质改为系统 Liquid Glass API；容器仍是 `HStack + Button`，因此只证明材质来自系统，不证明底栏是原生 `UITabBar` | Xcode 26 device build 与 54 屏回归见 `E-20260715-02`；2026-07-16 按用户反馈由 UI-006 纠正组件层级 | `eb240cc` |
| 2026-07-15 | CARD-002 | 按用户显式要求移除校园卡余额/付款码的录屏监听与黑色遮罩，录屏时内容保持可见 | 源码无 `isScreenCaptured`/`capturedDidChangeNotification`/旧提示文案；付款码 UI 回归及最终三条 macOS workflow 见 `E-20260715-02` | `eae0cd8` |
| 2026-07-15 | OPS-010 | 连续修复 Swift 可选值编译、父容器辅助功能标识覆盖子按钮、支付弹窗重复“确认”及 UI 等待/隐藏入口歧义；改为 6 秒确定性课表等待和设置页可见 Debug 行后，最终 117 单测、4 UI、54 屏全绿。严格 100% 尚需三类真实支付的外部解除条件，未以 Mock 伪造完成 | 失败诊断：`29358477320`、`29359233070`、`29361297708`、`29363068640`、`29364128467`；最终成功：CI `29366676954`、IPA `29366676886`、Archive `29366676870` | Android `fc150b0`；iOS `edfd219` |
| 2026-07-15 | PREF-004 | 纠正贡献名单迁移占位：移除 GitHub Contributors 外链页，按 Android `Contributors.kt` 和 `DeveloperViewModel.kt` 在 App 内展示加入我们与开发者卡片、头像、职责、QQ 和联系行为 | `ContributorsCatalogTests` 3 项及站内贡献名单截图在 CI `29366676954` 通过并目视复核 | `510b292`、`edfd219` |
| 2026-07-15 | CORE-004 | 完成 Apple 侧 Rust SDK/GuiXu 持久化：新增 C ABI 初始化与 KV 增删查清、结构化错误/panic 边界、登录/续期写回；Swift 业务缓存接入 GuiXu，按默认/文件域分 box、物理键哈希、账号隔离、旧 UserDefaults/文件缓存一次迁移和清理。Cookie 仍只在 ThisDeviceOnly Keychain，Apple 模式禁止写 GuiXu | Rust SDK 5 项、固定 GuiXu 5 项本地通过；CI `29366676954` 的 117 单测（含 2 项真实 FFI/迁移）、4 UI 全绿；IPA `29366676886`、Archive `29366676870` 成功 | SDK `e826156`；iOS `edfd219` |
| 2026-07-15 | PREF-005 | 按用户显式要求补回设置首页可见 `Debug` 行，并保留 Android 连续点击 App 卡片 8 次的兼容入口；UI 测试改走可发现入口 | CI `29366676954` 中 `settings.debug` → `operations.debug.screen` 路径及第 33 屏截图通过，并已目视复核 | `edfd219` |
| 2026-07-15 | UI-005 | 修复小工具“失物招领”和设置“意见反馈”的无效 SF Symbols：前者按 Android 原图分层组合包与问号，后者使用有效的感叹号气泡；新增共享符号清单、系统可用性单测与反馈入口 UI 断言 | CI `29369377322`：118 单测 + 4 UI 全绿，54 张 PNG 无失败附件；`06-tools` 目视通过；IPA `29369377575`、Archive `29369377896` 成功，证据见 `E-20260715-03` | `53cb7fd` |
| 2026-07-15 | AUDIT-001 | 对固定 Android 基线重新执行功能/路由/数据/平台完整复查并补齐原生导航/双返回手势、完整 Debug、自动续期与离线会话、真实下学期、多学籍排名、账号隔离缓存、首页拖放、跨周 Widget/提醒、Live Activity、主题/反馈/更新/许可证、流式下载分享和 AppIcon | SDK `cargo test` 7/7、`cargo check --features server`；最终 132 单测、5 UI、IPA 与 Archive 全绿，见 `E-20260715-04` | SDK `1177864`；iOS `565671e`～`18f96d5` |
| 2026-07-15 | AUDIT-002 | 继续收口低优先级复查项：天气页首入定位、PhotoKit 校历保存、Dynamic Type 缩放、不可逆校园卡缓存键、统一脱敏日志实际接入，以及续期凭据拒绝后的全局登录回退 | 最终 CI `29391015504` 通过 132 单测和 5 UI，双原生返回实拖与首页/工具去重入口均通过；IPA `29391015407`、Archive `29391015433` 成功 | iOS `0754440`、`7590212`、`7086948`、`18f96d5` |
| 2026-07-15 | OPS-011 | 全量复查候选完成最终验证，受影响切片从“待验证”恢复“已完成”；客户端可完成迁移仍为 20 / 23，只有三类真实支付受外部网关/授权环境阻断 | `E-20260715-04`；Artifact `AHUTong-ui-parity-xcresult-62`、`AHUTong-unsigned-ipa-62`、`AHUTong-release-readiness-16` | iOS `18f96d5`；SDK `1177864` |
| 2026-07-16 | UI-006 | 纠正“使用系统玻璃 API”等于“原生导航栏”的错误判断：删除自绘 `LiquidGlassBottomBar`，根四入口改为系统 `TabView`/`UITabBar`，每 Tab 独立导航栈，详情页由系统隐藏底栏；清理旧 96pt 覆盖补偿和无效玻璃开关 | CI `29432910807`：132 单测 + 5 UI 全绿，系统 Tab Bar 类型/标签、详情隐藏/恢复、左边缘与内容区域返回均通过；IPA `29432910913`、Archive `29432910832` 成功，首页系统 Liquid Glass 截图目视通过，见 `E-20260716-01` | `0a8f855`、`4bb2bab` |
| 2026-07-16 | UI-007 | 按用户要求从设置页彻底删除液态玻璃区块；系统原生 Tab Bar 默认启用并且不提供用户修改入口 | CI `29435300302`：132 单测 + 5 UI 全绿，三个删除项否定断言通过，偏好页截图目视通过；IPA `29435300525`、Archive `29435300113` 成功，见 `E-20260716-02` | `d5d791f` |
| 2026-07-17 | PAY-004 | 将三类生产支付的无服务端阻断提示改为学校官方 HTTPS/CAS 页面入口；真实输入与确认留在校方页面，App 不提交当前表单、不保存官方密码、不把跳转误报为成功，原生网关仍保持安全边界 | 最终 CI `29439249505`：无扣款 HEAD/302 探测、133 单测 + 5 UI 全绿；IPA `29439249117`、Archive `29439249504` 成功，见 `E-20260717-01` | `df88d87`、`ac5e1d0` |
| 2026-07-17 | PREF-006 | 覆盖此前可见 Debug 行要求：从设置“关于”列表删除 Debug，只保留 App 信息卡 8 连点隐藏入口；合并卡片辅助功能元素并用系统 8 连点做真实导航回归 | 最终 CI `29520243365` attempt 3：133 单测 + 5 UI 全绿；IPA `29520243324`、Archive `29520243338` 成功，见 `E-20260717-02` | `ec4f21a`、`64cc7df`、`4f00e8e` |
| 2026-07-17 | PREF-007 | 为设置首页、偏好开关、主题色、许可证和贡献者统一增加按压高亮、短缩放与轻触觉反馈；减弱动态效果时保留明暗反馈但取消缩放 | `SettingsInteractionTests` 2 项锁定按压/减弱动态效果状态；最终 macOS CI、IPA 与 Archive 见 `E-20260717-03` | `c68ff9a` |
| 2026-07-17 | SCH-005 | 对齐 Android `HorizontalPager`：课表主体改为原生 1～20 周分页，左右拖动跟手吸附，顶部周次与回到当前周双向同步；修正分页父级标识传播，保留当前页课程卡点击和辅助功能语义 | `ScheduleWeekNavigationTests` 覆盖周范围、边界与当前页课程标识；真实左滑 1→2 周、右滑 2→1 周及课程卡存在性由 UI 自动化验证，最终证据见 `E-20260717-04` | `aa4387f`、`ce732e0`、`7589911` |
| 2026-07-17 | ACA-006 | 修复考场查询：Rust 当前 HTML 解析移除运行时会崩溃的不支持 look-around，兼容表格换行、属性乱序、单双引号和两类座位号；iOS 对空字段/数字类型容错并增加考试卡 UI 标识 | Rust 9 项全绿（含 2 项新表格契约），Swift 解码 2 项及最终 macOS/IPA/Archive 见 `E-20260717-05` | iOS `1f23ee2`；SDK `ebf7024` |
| 2026-07-17 | SCH-006 | 修复课表设置中的无效 Alert Toggle：改为可交互 Sheet 与 Android 同款整行按钮；总览按同时间槽纵向分组，下学期独立加载并从教务 semesters 列表选择实际下一 ID | Rust 11 项、Swift 142 单测 + 6 UI 全绿；CI `29537917170`、IPA `29537917146`、Archive `29537917347`，见 `E-20260717-06` | iOS `b78bcde`；SDK `c8a5fb3` |
| 2026-07-26 | AUDIT-003 | 将产品参考更新到 Android 3.2.0 `2c33b0b`，分母由 23 增至 26；实现教学评价、招商银行充值、网费充值，并收口课表/首页/成绩/考试/校园卡/天气/失物/资料库/设置/隐私/GuiXu 持久化与许可证差异。客户端实现覆盖 26 / 26，11 个切片经新证据恢复完成后严格状态为 21 / 26；不把四类受阻原生扣款或未验真的招商银行账号链路记为完成 | Rust SDK 11 项、GuiXu 5 项；最终 CI `30211540807` 通过 203 单测 + 9 UI，IPA `30211540786`、Archive `30211540817` 成功，见 `E-20260726-01` | `02b3042`、`e6b4825`、`c02c168`、`61cee26` |
| 2026-08-01 | PAY-005 | PAY-01～03 接入 Android 同契约的真实只读数据链；PAY-04 增加纯原生 HEAD 扣款前验收；官方入口提供无凭据 HEAD 诊断；支付状态机在创建前持久化幂等键和不可逆请求指纹，丢失响应/重启不重复建单 | 最终 CI `30697541236`：277 单测 + 10 UI、实时 302 契约探测全绿；IPA `30697541215`、Archive `30697541230` 成功，见 `E-20260801-01` | `1e01069`、`c87c10a`、`9721ed8`、`1b47a34` |
| 2026-08-01 | SEC-001 | 完成 Swift/Rust/GuiXu 诊断隐私收口，覆盖认证头、Cookie、Token、URL 参数、嵌套编码、畸形 `%` 及 Basic/Bearer/Digest；禁止自动重定向的 URLSession delegate、官方目录 URL 规范化和 iOS 26 Alert/Tab UI 路径均以确定性测试锁定 | SDK 16 / 18 项、Swift 277 单测与 10 UI 全绿；失败候选 `30695338471`、`30696548830` 均记录真实根因后修复，最终证据见 `E-20260801-01` | SDK `18ab4b0`；iOS `9721ed8`、`1b47a34` |
| 2026-08-01 | PAY-006 | 以 Android `2c33b0b` 重审并恢复 PAY-01、PAY-02、PAY-03、PAY-05 原生生产支付：删除安全阻断与通用官方页，补齐客户端签名、409/430、入口预热、每订单安全键盘材料、最终提交、余额刷新、持久化未知状态和禁止重复建单；批准的 Android 客户端协议常量仅隔离在私有兼容层且不记录其值 | 最终 CI `30706286051`：333 单测 + 9 UI 全绿；IPA `30706286050`、Archive `30706286068` 成功，代码/产物敏感材料扫描及自动化禁真实扣款通过，见 `E-20260801-02` | `4e7d58e`、`20e4757`、`c15123b` |
| 2026-08-02 | AUTH-009 | 按 Android `2c33b0b` 修复真实 Session 过期链：Rust typed 错误与统一响应检查经本地服务返回 401；Swift 增加 App 级 single-flight、canonical Keychain、冷启动自动恢复、直连/校卡 Token 一次重试和支付写 POST 禁止重放；记录旧 500 根因，并修复 UI demo 提醒偏好触发真实认证请求的测试隔离缺陷 | CI `30710319015`：Rust 25 项、Swift 349 单测 + 9 UI 全绿；IPA `30710319019`、Archive `30710318991` 成功，见 `E-20260802-01` | SDK `e6c1df2`、`64b3564`；iOS `d194f9d`、`46b481c`、`bc35276` |
| 2026-08-31 | CARD-003 | 移除校园卡付款码展开态固定 `400pt` 高度与占满剩余空间的 Spacer，面板改由二维码、余额和内边距自然撑高，保留余额收起态 `140pt` 高度；独立 overlay 测量标记避免覆盖二维码原辅助功能标识 | UI smoke 锁定付款码面板高度小于 `300pt`；CI `33355172892` 通过 349 个单元测试与 9 个 UI 测试 | `9fcca9f`、`f62f4aa` |
| 2026-08-31 | REL-001 | 将 App 与 Widget 的 `MARKETING_VERSION` 统一设为 `1.0.0`，构建号继续保持 `1`；本次仅调整客户端版本配置，不执行上传或商店发布 | `project.yml` 双 target 版本字段静态复核；CI `33355172892` 完成 macOS/Xcode 构建与全量测试 | `f522279` |
| 2026-09-22 | ACA-007 | 为苹果官方与学校授权准备，从 iOS 整体移除教学评价：删除首页/工具/受限成绩入口、视图与模型、预设存储、Token/Cookie 会话引导、问卷读取/检查/提交 API 及相关单元/UI 测试；历史首页布局解码时自动清理已退役的 `evaluation` 卡片 | Windows 静态搜索、布局迁移测试与 `git diff --check`；macOS/Xcode 构建及回归待运行 | — |
| 2026-09-22 | AUTH-010 | 以官方 WebView 替换 iOS Rust 无头登录/OCR：隐私 v3 明确凭据用途与撤回，首登可见、教务前台隐藏续期、ADWMH 验证码可见降级；拒绝/撤回进入只含课表+设置的体验账户，支持历史缓存和 v1 JSON 导入 | 新增隐私决策、Web 安全策略、体验课表与 UI 测试；Android target `cargo check --features server` 通过，Apple check 因 Windows 缺少 `xcrun/clang` 停在环境边界，macOS/Xcode/真机待验证 | SDK `4d882f2`；iOS 待提交 |
| 2026-09-22 | AUTH-011 | 更新隐私政策与数据映射：首次 ADWMH 图形验证码由用户在可见页面手动填写；持续同意后，后续会话恢复可将当次验证码图片发送到安大通配置的远程识别接口，请求不附带账密/Cookie/Token/业务数据，App 不落盘或记录图片/结果，失败回退手动输入 | 文案与单元断言已更新；自动识别功能本轮未实现，启用前需固定识别接口域名/TLS与数据保留规则，并完成学校授权确认和真机可靠性测试 | iOS 待提交 |
| 2026-09-22 | AUTH-012 | 修复校园卡登录弹窗循环：首页校园卡余额 `.task` 改为静默会话策略，未授权时只显示缓存/占位；只有用户主动打开付款码等操作才允许弹出 ADWMH WebView；取消或失败后自动 `.task` 不重试，第二次未授权不重复发布登录通知 | CI `35735784509` 通过 353 单测 + 10 UI，`CampusCardInteractionTests` 2 项全绿；未签名 IPA `35735784456` 与 Release Archive `35735784573` 成功 | iOS `1226d2b`、`caba9f9` |
| 2026-09-23 | PREF-008 | 贡献名单展示名替换为用户指定别名、表情与零宽字符，移除五位贡献者的真实姓名；职责、QQ 与联系行为保持不变 | `ContributorsCatalogTests` 覆盖展示名与零宽字符；UI 测试改为校验 `s1nk`；Windows `git diff --check` | iOS 本次提交 |
| 2026-09-23 | PREF-009 / AUTH-013 | 对照 Android `develop` `e7d27ae` 补齐 MuxYang、InChange-Jiang；将账户、隐私和登录设置归入偏好设置；删除 iOS Debug 页/隐藏入口并改用真实 App 图标；修复 CAS 登录成功后原生凭据消息可能未到达导致的误报 | CI `35856636143` 通过 355 单测和 10 UI，设置/偏好/贡献名单截图目视通过；未签名 IPA `35857197483` 为 6,691,253 bytes，SHA-256 `863d957704b2e3a31b8a4c995d1adcf9b0ae01c8289133822e72ddb605c340f1`；真实校园登录须在授权真机验证 | iOS `9c98624` |
| 2026-09-23 | AUTH-014 / CARD-004 / CONTENT-004 | 登录页增加“暂不登录，使用体验账户”，已接受隐私的体验选择跨启动保持；校园卡余额/二维码及失物招领自动读取全部静默，只有显式“获取付款码”或“登录校园服务”启动 ADWMH 续期；保存校园卡请求可能轮换的 Cookie | `CampusSessionStoreTests`、`CampusCardInteractionTests`、`CampusAuthenticatedClientTests` 与登录 UI smoke 在 CI `35867866032` 通过；真实校园服务联调仍依赖授权账号 | iOS `edc346e` |
| 2026-09-23 | AUTH-015 | 按已披露的“首次手填、后续自动”补齐 iOS ADWMH 续期：只在 Keychain 已保存该域 Cookie 后启用隐藏 WebView，从校方同会话读取当次验证码，经 `openahu.org` HTTPS multipart `captcha` 上传图片，验证四位结果后用参数化 JavaScript 填入校方表单；OCR、页面或校验失败降级可见登录，后台不创建 WebView | CI `35867866032` 通过 362 单测、10 UI；未签名 IPA `35864415091` 为 6,716,992 bytes，SHA-256 `ab68591fa22623242ea18af50961f485636a262e20709615ce2df341e161c636`；真机验证码与服务端保留规则待验证 | iOS `f926316`、`63d81c0` |
| 2026-09-23 | AUTH-016 | 修复可见 ADWMH “绑定账号”点按无反馈：对校方页面的空 `javascript:` 链接移除无效导航目标，仍由原 jQuery 点击脚本提交；转发可信主框架的网页 `alert` 到系统提示，并对提交中、Ajax 失败与超时给出可见反馈；隐藏自动登录遇到校方弹窗立即降级可见页 | CI `35876264502` 通过 363 单测、10 UI；未签名 IPA `35876283927` 为 6,726,404 bytes，SHA-256 `3d8cebea68f2bcdc4a8097bf7b21624f02bb5fa87757df1ddcfccc43aa6fb402`；授权账号真机绑定待验证 | iOS `f3e927f` |
| 2026-09-24 | AUTH-017 | 真机反馈“OPENID 获取失败”后对照 Android `develop` `e7d27ae` 纠正 ADWMH 入口：可见 WebView 保留校方验证码与同会话 Cookie，拦截原账号绑定点击，按 Android 字段 `username/pwd/flag=0/imgcode` 向校方 `/user/login` 提交；隐藏 OCR 续期也复用该接口，只有 JSON `code=10000` 才导出 Cookie 并由原生只读接口复验，完全避开 `/index/user/account/bind` | CI `35884531118` 通过 366 单测、10 UI；未签名 IPA `35884547808` 为 6,740,724 bytes，SHA-256 `202b15b137ddae867f4c9da1ca48480650cc924627b987a1a53a656625f81c0f`；授权账号真机仍待验证 | iOS `c549cc7` |
| 2026-09-24 | AUTH-018 / CARD-005 | 真机确认手动登录成功但余额仍旧、二维码展开仍需再点：修复 SDK 原生 NDJSON Cookie 存档误写 Keychain，改用扁平 Cookie 快照并在冷启动迁移旧格式；展开二维码自动静默读取与优先隐藏续期，只有显式失败重试可拉可见登录；登录成功事件立即刷新余额并防止旧请求覆盖新结果。WidgetKit 扩展已存在且包含在 IPA 中，无需标“开发中” | 新增旧快照迁移、自动隐藏续期、余额再次读取测试；Windows `git diff --check`，macOS CI `35901490865` 全绿，授权账号真机待验证 | iOS `60748b2` |
| 2026-09-24 | PREF-010 | 应用户要求纠正 `9c98624` 的设置分组：账户信息卡及“登录真实账号/重新登录”恢复到设置首页；偏好设置仅保留隐私选择与政策入口等偏好项，体验账户的同意后登录路径继续可用 | 设置与体验账户 UI smoke 新增首页账户入口和偏好页无账户入口断言；Windows `git diff --check`，macOS CI `35901490865` 全绿 | iOS `75667b3` |
| 2026-09-24 | CARD-006 / CONTENT-005 | 校园卡隐藏续期失败时增加仅含阶段原因的临时测试 Toast，保留凭据并降级可见登录；二维码图像点击强制刷新付款码及余额；失物招领只读响应接受 Android 校园服务成功码 `10000`，写操作仍遵守原契约；旧版 Cookie 快照仅在识别到原生 NDJSON 且转换结果非空时迁移，避免离线快照被空数组覆盖 | 对照 Android `develop` `e7d27ae` 的二维码点击与 ADWMH 成功码；新增失物招领响应码、旧快照识别和二维码点击测试；最终 CI `35901490865` 373 单测、10 UI 全绿，IPA #120 与 Archive 成功；真机错误阶段仍需用户验证 | iOS `d0ccac1`、`ab5c356` |
| 2026-09-24 | CARD-007 / AUTH-019 | 真机 Toast 明确失败于获取校方验证码图片；隐藏 WebView 继续建立同域会话，图片改为带该会话 Cookie 的原生 GET，禁止跟随重定向并合并响应 Cookie，再将图片送远端 OCR。失败 Toast 细分为缺少会话、网络、重定向、HTTP 状态和非图片 | Android `develop` 的 `/remind/authcode` 原生 GET 契约；URLProtocol 本地取图与 Cookie 测试、`git diff --check`；macOS CI `35956666651` 384 单测、10 UI 全绿；真机已进入远端 OCR，最终自动续期仍待验证 | iOS `f250654` |
| 2026-09-24 | CARD-008 / AUTH-020 | #121 真机反馈显示验证码图片已成功获取，故障转移到远端 OCR；按图片格式选择 multipart MIME，JPEG 对齐 Android `image/jpg`，OCR 等待从 10 秒增至 20 秒、隐藏总超时为 30 秒，并细分安全错误 Toast | Android `develop` `AhuTong` 的 HTTPS `/ocr/captcha`、`result` 字段与 `image/jpg` 上传；URLProtocol 本地 OCR 失败分类测试；最终 CI `35956666651` 384 单测、10 UI 全绿；#122 真机曾遇临时网络失败，随后 Safari 已恢复，用户确认无需继续修复 | iOS `b2009ef` |
| 2026-09-24 | CARD-009 / AUTH-021 | 用户明确将“一次手动输入”限定为 App 官方首次登录；取消校园服务首次需历史 Cookie/手填验证码的门槛，前台隐藏 WebView 从首次 ADWMH 请求起使用 Keychain 凭据、同域取图及远端 OCR，失败提示重试而不弹第二登录页。隐私政策升级 v4 并要求重新确认，读请求最多重试一次，写请求不自动重放 | 无 Cookie 建立验证码会话、纯策略、首屏余额/付款码、失物招领和隐私版本测试；CI `35959882196` 388 单测、10 UI 全绿，IPA #123 与 Archive 成功；授权真机待验证 | iOS `0daa63f` |
| 2026-10-14 | AUTH-022 / SCH-007 / HOME-004 | 修复网络校验阻塞开屏、周数字段误读、地区设置换周、演示偏好残留及下学期日期伪推算；保留按账号/学期隔离的离线周锚点，旧校验和旧课表请求不能覆盖新状态；补充申请制 Ad Hoc OTA 分发方案与第三方应用授权边界 | 本机 Xcode 27：401 单测 + 2 UI 全绿，见 `E-20261014-01`；授权真机待验收 | 本分支 |
| 2026-10-14 | CARD-010 | 弱网首页优先预取付款码并取消慢余额请求；续期不等待余额验证；补齐内存年龄、后台清理和旧响应保护，按本机预览后推送/打包的顺序交付 | 最终本机 410 单测 + 3 UI 全绿，预览与边界见 `E-20261014-02` | 本分支 |
| 2026-10-19 | AUTH-023 / ACA-006 / SYS-003 / UI-007 | 按用户七项顺序完成 PR 审查与维护：临时续期保留凭据、Cookie 轮换与账号隔离、成绩/考试缓存提示、校园时区和实际节次、小组件包与共享组检查、缴费键盘完成入口；校准完成计数，SYS-01 重开真机验证，更新 25 人问卷计划及失效手册 | 本机 423 单测；5 个受影响 UI 用例通过复验；Release iphoneos 构建与最终 IPA 结构校验通过，首轮失败及真机边界见 `E-20261019-01` | iOS `bd4335f` 与本次文档提交 |
| 2026-10-19 | UI-008 / PREF-011 | 复核系统 TabView 四入口、无 Debug/玻璃设置、真实图标和账户位置；修复偏好行高亮越界，精简提示，删除不可达弹窗，小组件指引适应大字体 | 5 项设置单测、3 条 UI 分别通过；真实系统减弱动态效果及深色大字体截图/录屏、Release device 构建与新 IPA 结构校验见 `E-20261019-02`；真机边界保留 | 本次提交 |
| 2026-10-19 | UI-009 / APP-003 | 按 Android 3.2.2 实际路径替换原生 Tab 的四个轮廓矢量，开屏改用 App 图标，补齐离线图标许可；开发与预览默认关闭减弱动态效果，专项后恢复关闭 | 6 单测复验全绿、3 UI 通过，真实导航截图/完整动态效果录像与深浅色开屏视图、最终 Release 及 IPA 见 `E-20261019-03`；保留首轮漏资源失败 | 本次提交 |


| 2026-10-19 | SCH-008 / OPS-004 | 修复课表 Tab 重入回跳并拆分 CI，保留 #3 包含关系和 #2 暂缓决定 | 独立模拟器单测、启动/日期/Tab 回归，见 E-20261019-04 | 本次提交 |

| 2026-10-19 | SYS-004 | 合入实时活动双倒计时、后台持续计时与独立偏好，沿用校园日历与真实节次 | 分支证据 E-20261019-LIVE-01，集成回归见 E-20261019-05 | `89975b7` 与本次集成 |

| 2026-10-19 | SYS-005 | 合入付款码和指定日期课表 App Intents；保留维护分支的周次验证、缓存锚点、请求隔离和二维码预取 | 原分支 `5f92a1c`，集成回归见 E-20261019-05 | 本次集成 |

| 2026-10-19 | REL-002 / SYS-03 / PREF-012 | 集成维护、实时活动与快捷指令；设置新增原生系统快捷指令入口和简洁引导；App/Widget 升为 1.0.1 (2) | 见 E-20261019-05 | 本次提交 |

| 2026-10-19 | UI-010 / PREF-013 / SYS-006 / REL-003 | 校园码展开与放大、课表正圆周次、设置返回根页、与相邻卡片一致的偏好内 Siri 引导、紧凑课表回复与随机双排头像；贡献使用系统浮窗，关闭自动续滚；新增 Himekawa；岛卡改为仅课前显示，App/Widget 统一 1.0.2 (3) | 实现及验证见 E-20261019-06；旧断言按新需求更新，保留失败记录与真机边界 | 本次提交 |
