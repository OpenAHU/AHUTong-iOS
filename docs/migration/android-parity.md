# Android → iOS 迁移长期路线图

> 本文件是 iOS 迁移任务的唯一进度源。每完成一个可独立验收的功能切片，必须在同一次改动中更新状态、验证证据、关联提交和变更日志。

## 当前摘要

| 项目 | 当前值 |
| --- | --- |
| 总体状态 | 客户端迁移收口；真实支付仍外部阻塞 |
| 当前里程碑 | 四入口已改为系统 `TabView`/`UITabBar`，并完成 Xcode 26.5 全量 CI、未签名 IPA 与 Release Archive 验证 |
| 当前焦点 | 系统原生 Liquid Glass Tab Bar、每 Tab 独立导航栈、详情页系统隐藏/恢复底栏，以及原生左边缘/内容区域返回均已收口 |
| 下一步 | 用户在 iPhone 13 Pro 真机验证系统 Liquid Glass、导航手势和 7 天签名安装；支付负责人提供 D-005 网关与授权环境后验收 PAY-01～03 |
| 用户/平台功能进度 | 20 / 23 个切片满足严格完成定义（87.0%）；剩余 3 个均为受 D-005、R-003、R-004 外部依赖阻断的真实支付切片，不以 Mock 冒充完成 |
| 当前分支 | `codex/feat/android-parity-migration` |
| 最近更新 | 2026-07-16 |

## 1. 目标与边界

### 1.1 长期目标

在 iOS 上以 Swift 和 SwiftUI 重建 AHUTong 的核心体验，使登录、课表、首页、学业查询、校园服务及系统集成达到可验证的 Android 行为对齐，同时遵循 iOS 的交互、安全、隐私和发布规则。

迁移以固定 Android SHA 的代码与该版本实际渲染结果为唯一产品基准。业务实现不逐行翻译 Kotlin，但用户可见 UI 必须逐屏、逐状态对齐 Android；Android 中已知的安全问题、无效设置、提前提示成功等缺陷不得复制到 iOS。

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

### 1.4 UI 完全一致硬约束

1. 固定基线表中的 Android commit 及其 Compose 实际渲染结果是唯一视觉真源；不得以“更符合 iOS”“更简洁”或个人审美为由重新设计。
2. 页面信息架构、组件类型、内容顺序、中文文案、图标语义、颜色、字号/字重、圆角、阴影、间距、留白、对齐、卡片尺寸、列表密度、底栏和顶部栏必须与 Android 保持一致；第 8、9 条记录的用户显式覆盖除外。
3. 正常、加载、空数据、错误、弹窗、菜单、搜索、展开/收起、刷新和权限降级等可见状态都必须逐一对齐；不能只对齐首屏静态状态。
4. iOS 只允许保留系统强制差异：安全区、Home Indicator、系统权限弹窗、系统返回手势、拨号/分享/Quick Look 等系统控制器。差异必须限制在系统边界内，并记录在平台差异表中。
5. SwiftUI 可以使用等价实现，但不得用默认 `List`、`Form` 或系统导航样式替代 Android 已明确设计的自定义外观；需要时应以自定义组件复现 Compose 布局。四入口底栏仅按第 8 条用户显式覆盖使用系统 `TabView`。
6. 每个页面完成前必须保存同一设备尺寸、同一数据状态的 Android 与 iOS 截图，检查关键几何尺寸与颜色；主要页面必须有 UI 测试覆盖可见文案、入口和交互状态。
7. 本约束追溯适用于此前已标记完成的 APP-01、AUTH-01、INFO-01、INFO-02、INFO-03、CONTENT-03；这些切片在 UI 复验通过前统一回到“实现中”。
8. 2026-07-16 用户进一步明确四入口必须使用 iOS 原生底部导航，而非仅在自绘容器上调用 Liquid Glass API。根容器必须使用系统 `TabView`/`UITabBar`，iOS 26+ 的 Liquid Glass、折射、触控、辅助功能和后续系统演进全部交给系统；禁止自绘 `HStack + Button` 冒充原生 Tab Bar。入口顺序、图标、中文文案和选中语义仍与 Android 一致。
9. 2026-07-15 用户显式要求设置首页直接显示 `Debug` 入口。Android 的 App 卡片连续点击 8 次入口仍保留为兼容路径，iOS 同时提供可发现的 `Debug` 行；Debug 页面内容和视觉仍以 Android `settings/Debug.kt` 为基准。

## 2. 固定基线

| 仓库 | 基线 | 说明 |
| --- | --- | --- |
| AIO | `031ed3c2c599240a62184d928c3bcfbb22866607` | 迁移 worktree 的 detached HEAD |
| Android | `2a30a54e74127ce1b4f75763596b470bd0b9d01b` | 本路线图的功能与代码参考基线 |
| iOS | `96d33412ae47471d209b2e21c7b9715fc278d4f9` | 迁移开始前的 `main`；仅含两行 README |
| Android `sdk` gitlink | `8c2d6b8113cb0f2ea6bb45cd74fa950e39dc956d` | 已按需浅拉，并固定为 iOS `Vendor/sdk` 的业务实现基线 |
| iOS `sdk` 适配 | `1177864f4063b65220dc18c6742fb5d7ebe45ae5` | 在 Apple C ABI、GuiXu KV、Cookie 安全模式与持久化错误边界上继续补齐下学期课表、多学籍与成绩排名服务接口；已推送分支 `codex/feat/apple-guixu-persistence` |
| Android `GuiXu-Rust` gitlink | `2481ab378395b5ee6db21021524ad051d98b888f` | 已按需浅拉，并固定为 iOS `Vendor/GuiXu-Rust` 的解析依赖基线 |

基线不得静默替换。Android 参考版本变化时，必须在这里追加新 SHA，并在变更日志说明重新对照了哪些功能与契约。

迁移起点的 iOS 仓库只有两行 README；当前已建立 XcodeGen 工程、SwiftUI 源码、单元/UI 测试、资源、CI、`.gitignore` 和 `AGENTS.md`，`LICENSE` 与正式签名参数仍待确定。当前本地开发环境为 Windows，不能运行 `xcodebuild`；macOS CI 已完成 Simulator 构建测试、Apple device 静态库与未签名 iphoneos App/IPA 构建，物理 iPhone 安装和系统能力仍需用户实测。

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
7. 不包含密码、Token、Cookie、支付签名、账号、签名证书或其他敏感信息。
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
| Compose `NavHost` / 底栏 | 系统 `TabView` 承载四入口，每个 Tab 使用独立 `NavigationStack`；详情页以系统 toolbar 语义隐藏 Tab Bar |
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
| D-003 | Rust crate 是否支持 Apple target、staticlib/XCFramework 及 C ABI/UniFFI | 已完成 spike 与持久化适配 | SDK `e826156` 在原 Simulator/device `staticlib` 基础上补齐 GuiXu 初始化、KV 增删查清、结构化错误和 panic 边界；本阶段不额外封装 XCFramework，构建脚本按 Apple target 选择静态库 |
| D-004 | Rust 直连 FFI、本地 loopback HTTP 或 Swift `URLSession` 的主数据方案 | 已确定开发期方案 | C ABI 负责生命周期及 GuiXu 持久化/KV；业务请求继续使用带随机 token 的 localhost Rust server + Swift `URLSession`，只开放 loopback，保留未来逐接口直连 FFI 的替换边界 |
| D-005 | 支付签名与客户端凭据的服务端化、轮换方案 | 阻塞支付 | 2026-07-15 对 OpenAHU 可见仓库和组织代码执行只读检索，未找到可接入的服务端支付签名/对账网关；必须由支付负责人完成已暴露材料轮换并提供网关 URL、鉴权契约及授权测试环境后，才能进入三类真实支付验收 |
| D-006 | macOS CI、Simulator 设备矩阵与真机验证负责人 | 最终 Simulator、未签名 IPA 与 Release Archive 均通过 | 最终 CI `29391015504` 在 Xcode 26.5、iPhone 13 Pro / iOS 26.5 Simulator 上通过 132 个单元测试与 5 个 UI 测试，包含原生左边缘/内容区域返回实拖验证；Artifact `AHUTong-ui-parity-xcresult-62`。设备 run `29391015407` 与 Archive run `29391015433` 成功；物理 iPhone 13 Pro 验证由用户执行 |
| D-008 | 当前无付费 Apple Developer Program 账号时的真机分发方式 | 已确定开发期方案 | GitHub Actions 只生成未签名 IPA；Apple ID 不进入仓库或 GitHub Secrets；本机使用 Personal Team/Sideloadly 或 AltStore 签名，每 7 天刷新；该方式不等同于 TestFlight/App Store 发布 |
| D-007 | 崩溃上报、灰度、统计与广告方案 | 已确定当前方案 | 当前不集成第三方崩溃、统计或广告 SDK；灰度只向自有端点发送不可逆账号摘要并提供本地兜底；未来新增数据收集必须先更新隐私清单和用途评估 |
| D-009 | Android 三个首启弹窗在 iOS 的同意语义 | 已确定开发期方案 | 免责声明与隐私说明为必要确认；社区/商业合作仅供自愿阅读，不阻塞使用；拒绝时留在协议页且不保存状态，不主动退出 App；正式发布文本仍需隐私/合规复核 |

## 7. 里程碑

| 阶段 | 目标 | 出口条件 | 状态 |
| --- | --- | --- | --- |
| P0 | 契约、安全与工程基线 | 完成关键决策；建立 DTO/golden fixtures；Rust/Swift 数据方案有结论；无敏感信息入库 | 实现中（许可证/正式签名待定） |
| P1 | App 骨架与离线样例 | SwiftUI 四入口、主题、导航、依赖注入、Mock、单测/UI smoke 可在 macOS CI 运行 | 已完成 |
| P2 | 核心闭环 | 登录/退出/恢复会话、课表、首页今日课程、离线缓存、多账号隔离完整 | 已完成 |
| P3 | 教务域 | 成绩/GPA、考试、空闲教室契约与 UI 完整 | 已完成（3 / 3） |
| P4 | 低风险校园服务 | 余额/二维码、失物只读、校历、天气、电话本、学习资料完整 | 已完成 |
| P5 | 写操作与支付 | 失物发布/删除和三类支付通过安全、幂等、失败恢复及真机验证 | 外部阻塞（失物写操作与支付客户端完成；3 个真实支付验收受 D-005 阻断） |
| P6 | 平台增强 | WidgetKit、课程提醒、可选 Live Activity、后台刷新与辅助功能完整 | 已完成（WidgetKit、跨周提醒、ActivityKit、前台/时区维护与 Dynamic Type） |
| P7 | 发布 | Release Archive、签名、权限文案、隐私清单、TestFlight/App Store 清单完整 | 工程收口（OPS-01 完成；正式许可证、付费签名/TestFlight 不属于当前 Personal Team 方案） |

## 8. 功能迁移矩阵

说明：Android 路径均相对于 Android 子仓根目录。`—` 表示尚无验证或提交证据。完成行共享证据 `E-20260714-01`：Android 固定参考 SHA `2a30a54`，仅含测试/固定数据的证据分支 commit `b063581`，CI `29327068093` 与 29 张 1170×2532 PNG 的 UI run `29327068134` 均成功；iOS code commit `6561f25` 的 CI `29331379333` 在 Xcode 26.5（17F42）、iPhone 13 Pro / iOS 26.5 Simulator 上通过 68 个单元测试、2 个 UI 测试，Artifact `AHUTong-ui-parity-xcresult-37` 含同尺寸 29 张 PNG；设备 run `29331379344` 成功上传 3,740,282 bytes 的 `AHUTong-unsigned-ipa-37`。两侧正常、加载、空、错误、弹窗和详情截图已逐屏审查，允许差异仅限第 9 节记录的平台边界。

本轮新增完成行共享证据 `E-20260715-01`：Android 产品参考仍固定为 `2a30a54`，证据分支仅增加测试与确定性 fixture，commit `887a0c5` 的 CI `29351110964` 和 UI run `29351111083` 均成功，Artifact `AHUTong-android-ui-baseline-19` 含 43 张 1170×2532 PNG；iOS code commit `77a5ae5` 的 CI `29353937788` 在 Xcode 26.5（17F42）、iPhone 13 Pro / iOS 26.5 Simulator 上通过 87 个单元测试、3 个 UI 测试，Artifact `AHUTong-ui-parity-xcresult-46` 含同尺寸 43 张 PNG 且无缺图；设备 run `29353938071` 上传 4,211,678 bytes 的 `AHUTong-unsigned-ipa-46`，SHA-256 为 `81F454EE79F2FB343E49BEB39DE7E05CA6E9B5B79B0FC7B7D5A1B7561466FF20`，包内确认包含 `AHUTongWidget.appex`。新增空闲教室、失物列表/详情/发布、Widget 预览、提醒开关及登录/数据三态均完成双端逐屏审查；真实校园账号和物理 iPhone 只作为部署环境回归，不冒充已执行证据。

收口证据 `E-20260715-02`：Android 产品参考继续固定为 `2a30a54`，证据分支 commit `fc150b0` 只扩展 UI 自动化，Android CI `29359831800` 与 UI run `29359831897` 均成功，Artifact `AHUTong-android-ui-baseline-20` 含 48 张 1170×2532 PNG；新增校园卡充值正常/确认弹窗、浴室正常、电控正常和隐藏 Debug 五屏已逐张目视检查。iOS commits `c091244`、`eb240cc`、`eae0cd8`、`510b292`、`5468999`、`edfd219` 已分别完成支付/运维、调用系统 Liquid Glass API 的自绘底栏、移除录屏遮罩、站内贡献名单、支付按钮唯一标识，以及 Apple GuiXu/旧缓存迁移/可见 Debug 入口。SDK `e826156` 补齐 Apple GuiXu C ABI 与 Keychain-only Cookie 模式；Rust SDK 5 项、固定 GuiXu 5 项本地测试，以及 CI `29366676954` 的 117 个单元测试、4 个 UI 测试均通过。Artifact `AHUTong-ui-parity-xcresult-54` 含 54 张 1170×2532 PNG，无失败关联附件；设置页可见 Debug、Debug 页面和站内贡献名单已目视复核。设备 run `29366676886` 上传 `AHUTong-unsigned-ipa-54`，其中 IPA 为 4,515,159 bytes，SHA-256 `5b268279de7059e8c7dda4c1d0adb1628591c0245d6d8053de17834f3b6fb318`；Archive run `29366676870` 上传 `AHUTong-release-readiness-8` 并通过 App/Widget、双隐私清单、dSYM 与敏感信息边界校验。支付截图为不可扣款 Mock，只证明客户端 UI/状态机，不替代 D-005 服务端网关与授权环境验收；该版底栏只是系统玻璃材质作用于自绘结构，不作为原生 `UITabBar` 证据。

图标回归证据 `E-20260715-03`：对照 Android 固定基线的 `lost_and_found.xml` 与 `Icons.Outlined.Feedback`，iOS commit `53cb7fd` 移除不存在的 `questionmark.bag`、`bubble.left.and.exclamationmark`，失物招领改为稳定的 `bag` + `questionmark` 分层组合，意见反馈改为 `exclamationmark.bubble`。CI `29369377322` 在 iPhone 13 Pro Simulator 上通过 118 个单元测试和 4 个 UI 测试；`AndroidParityIconTests` 确认三个底层 SF Symbols 均可创建，`settings.feedback` UI 入口断言通过。Artifact `AHUTong-ui-parity-xcresult-55` 含 54 张 PNG 且无失败关联附件，`06-tools` 已目视确认蓝色包与问号完整显示；设置主屏截图下部受浮动底栏遮挡，因此反馈图标以专项符号测试和 UI 入口断言作为可复现证据，不虚构目视结论。未签名 IPA run `29369377575` 与 Release Archive run `29369377896` 同时成功。

全量复查收口证据 `E-20260715-04`：Android 产品基线继续固定为 `2a30a54`，iOS 最终代码 commits `565671e`、`a0d4855`、`444d2d3`、`0754440`、`7590212`、`7086948`、`18f96d5`，SDK `1177864f4063b65220dc18c6742fb5d7ebe45ae5` 已推送。最终 CI `29391015504` 在 Xcode 26.5、iPhone 13 Pro / iOS 26.5 Simulator 上通过 132 个单元测试和 5 个 UI 测试；原生导航专项实际执行左边缘拖动与两个内容坐标有限重试的内容区域拖动，两条路径均返回工具页。Artifact `AHUTong-ui-parity-xcresult-62` 为 18,811,420 bytes，SHA-256 `e1c8410c1299176e9a8f2ae99a3474265aaebcacbb9fd721937ed758b7e5a6f4`。未签名 IPA run `29391015407` 上传 `AHUTong-unsigned-ipa-62`；其中 IPA 为 5,496,416 bytes，SHA-256 `EB21B418F0B2839EBD02E3CA2F30CF13BB370D5979FD84F9AF1EC77896A6F051`。Release run `29391015433` 上传 9,592,955 bytes 的 `AHUTong-release-readiness-16`，完成 App/Widget/ActivityKit、AppIcon、隐私清单、dSYM 与敏感材料边界审计。PhotoKit、定位、通知和 Live Activity 的物理效果仍需用户真机部署回归；这不替代三类真实支付的 D-005 外部验收。

原生底栏修复证据 `E-20260716-01`：根 App Shell 已删除 `LiquidGlassBottomBar` 的 `HStack + Button` 自绘实现，改由系统 `TabView` 生成 `UITabBar`；四个入口各自持有 `NavigationStack`，详情页使用 `.toolbar(.hidden, for: .tabBar)` 交给系统隐藏/恢复，四个一级页删除旧覆盖栏所需的 96pt 补偿。代码 commits `0a8f855`、`4bb2bab` 已推送。最终 CI `29432910807` 在 Xcode 26.5、iPhone 13 Pro / iOS 26.5 Simulator 上通过 132 个单元测试和 5 个 UI 测试；UI 自动化明确从 `XCUIElementTypeTabBar` 下操作四个系统标签按钮，并验证详情页隐藏、两种原生返回手势及返回后底栏恢复。Artifact `AHUTong-ui-parity-xcresult-64` 为 19,622,549 bytes，SHA-256 `c99bfa483f0a948a6c79511dfc7ec6b3d4bd67c8958fa23178a6e23811fcea24`，含 54 张截图且无失败关联附件；首页截图已目视确认系统 Liquid Glass 胶囊、系统选中态和四入口完整。未签名 IPA run `29432910913` 上传 `AHUTong-unsigned-ipa-64`，其中 IPA 为 5,470,527 bytes，SHA-256 `031285173E231B3659DBF417C8DD9751AE9DB34E033ECFB09236148905254403`；Release run `29432910832` 上传 9,547,511 bytes 的 `AHUTong-release-readiness-18`。首次 CI `29431825512` 的 3 条旧 identifier 失败作为测试迁移诊断保留，不计为最终验证。

| ID | 功能切片 | Android 参考 | iOS 目标 | 优先级 / 依赖 | 状态 | 核心验收 | 验证 / Commit | 更新 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| APP-01 | App Shell、四入口与统一状态 | `ui/screen/Main.kt`、`BottomNavBar.kt` | `App/`、`Core/DesignSystem/` | P1 | 已完成 | 主页/课表/小工具/设置顺序、图标、文案、选中态、Android 色板/卡片/标题/搜索组件和统一页面背景保持不变；按用户显式覆盖，底栏由系统 `TabView`/`UITabBar` 承载，iOS 26+ 自动采用系统 Liquid Glass；每个入口保留独立导航栈，详情页由系统隐藏底栏 | 原双端对照见 `E-20260714-01`；系统 Tab Bar 类型、四标签、隐藏/恢复和双返回手势最终回归见 `E-20260716-01`；Commits `0a8f855`、`4bb2bab` | 2026-07-16 |
| AUTH-01 | 启动、三份协议与首登流程 | `ui/screen/Splash.kt`、`ui/screen/setup/*` | `Features/Onboarding/` | P1 / APP-01 | 已完成 | Android 对话框几何、内容滚动区、按钮和三页标题顺序已对齐；同意状态持久化，拒绝与再次查看路径明确 | `AgreementConsentStoreTests` 3 项通过；双端首启三弹窗证据见 `E-20260714-01`；Android 非活动旧弹窗残影不复制，见第 9 节；Commits `430bd45`、`d15a207`、`6561f25` | 2026-07-14 |
| AUTH-02 | 登录、会话恢复、过期重登与退出 | `Login.kt`、`LoginViewModel.kt`、`AHURepository.kt`、`crawler/manager/*`、`sdk/*` | `Core/Auth/`、`Features/Login/` | P2 / D-003~D-005 | 已完成 | 固定 Rust SDK 的验证码/CAS/Cookie 链路以 Apple staticlib 接入；初始化 GuiXu 前先清空 Rust 内存 Cookie，iOS 以 `persist_session=0` 禁止 Cookie 写入 GuiXu，冷启动只从按学号隔离的 ThisDeviceOnly Keychain 恢复，过期时凭据重登，无凭据时安全清理，退出同时清理会话与 Widget 快照 | `CampusSessionStoreTests` 4 项、`CredentialStoreTests` 4 项及登录正常/工作中/错误状态在 `E-20260715-01` 全通过；SDK Keychain-only 持久化及最终 macOS 验证见 `E-20260715-02`；授权校园账号与物理机属于部署回归；Commits `d8516f2`、`77a5ae5`、`edfd219`，SDK `e826156` | 2026-07-15 |
| SCH-01 | Course 模型、周次解析、API 与离线缓存 | `data/model/Course.java`、`CurrentWeekResolver.kt`、`SdkDataSource.kt`、`AHUCache.kt` | `Core/Models/`、`Features/Schedule/Data/` | P2 / AUTH-02 | 已完成 | `/schedule`、`/schedule/current-week` 真实 SDK 数据源已接入 cache-first/refresh/stale-cache Repository；业务缓存通过 Apple C ABI 写入 GuiXu，物理键为 SHA-256 摘要且逻辑键强制账号命名空间；升级时一次性读取旧 UserDefaults/文件缓存、写入 GuiXu 后删除旧副本；Widget 快照与提醒刷新仍由同一课表结果驱动 | 原课表 Repository/文件缓存/周次/模型 12 项及新增 GuiXu FFI/迁移 2 项测试；全状态 UI 见 `E-20260715-01`，最终 macOS 复验见 `E-20260715-02`；Commits `d8516f2`、`edfd219`，SDK `e826156` | 2026-07-15 |
| SCH-02 | 课表 UI、课程详情与设置 | `main/Schedule.kt`、`ScheduleViewModel.kt`、`main/schedule/*` | `Features/Schedule/` | P2 / SCH-01 | 已完成 | 20 周、真实日期、单双周卡片、重叠课程分栏、刷新、总览、课程详情、真实下学期切换和设置已按 Android 几何实现；加载/空/错误态完整 | 课表/周次/模型/缓存与真实学期边界测试通过；原 UI 证据见 `E-20260714-01`，最终下学期与导航复验见 `E-20260715-04` | 2026-07-15 |
| HOME-01 | 首页概览与 8 槽位自定义 | `main/Home.kt`、`main/home/*`、`DiscoveryViewModel.kt`、`data/gray/*` | `Features/Home/` | P2 / APP-01、SCH-01 | 已完成 | 今日课程、天气、8 槽位去重/增删/换位、编辑工具库与持久化已实现；Android 10 个工具注册表保持同序 | `HomeWidgetLayoutTests` 5 项覆盖布局和固定时间的进行中/下一节/已结束状态；首页正常及三种状态双端证据见 `E-20260714-01`；Commits `e339a7b`、`b3c098c`、`f23f130` | 2026-07-14 |
| ACA-01 | 成绩、多学籍、GPA 与专业排名 | `main/Grade.kt`、`GradeViewModel.kt`、`data/model/Grade*` | `Features/Grades/` | P3 / AUTH-02 | 已完成 | SDK `/grade`、`/grade/profiles`、`/grade/rank`、递归兼容解析、真实多学籍切换、GPA/学期排名、学期筛选、搜索、账号隔离离线缓存和全状态 Android UI 已实现 | Rust 多学籍/排名解析 2 项及 Swift 成绩回归通过；原四状态证据见 `E-20260714-01`，最终 SDK/CI 见 `E-20260715-04` | 2026-07-15 |
| ACA-02 | 考试查询 | `main/Exam.kt`、`ExamViewModel.kt`、`data/model/Exam.java` | `Features/Exams/` | P3 / AUTH-02 | 已完成 | 固定 SDK `/exam`、刷新、搜索、进行中/未开始/已结束、时间、考场、座号和加载/空/错态均已实现；状态排序使用与 Android 相同的确定性基准时间 | `CampusExamDisplayStatusTests` 2 项通过；考试正常、加载、空、错误双端证据见 `E-20260714-01`，首卡均为“操作系统 / 进行中 / 09:40~11:20”；Commits `bbabd5e`、`ffe9887`、`6561f25` | 2026-07-14 |
| ACA-03 | 空闲教室 | `main/FreeClassroom*.kt`、`FreeClassroomViewModel.kt` | `Features/FreeClassroom/` | P3 / AUTH-02 | 已完成 | 真实楼栋 GET 与空闲列表 POST 契约、校区/楼栋多选、节次、日期范围、查询结果和加载/空/错状态完整；页面标题、紫色查询按钮、12 间确定性结果和卡片密度与 Android 对齐 | `FreeClassroomTests` 4 项及双端正常/加载/空/错误截图在 `E-20260715-01` 通过；Commits `d8516f2`、`1c0f950` | 2026-07-15 |
| CARD-01 | 校园卡余额与付款码 | `home/CampusCard.kt`、`AHURepository.kt`、`TokenManager.kt` | `Features/CampusCard/` | P4 / AUTH-02 | 已完成 | 余额刷新、动态二维码、凭据过期和刷新/关闭工具栏完整；按用户要求移除录屏状态监听及付款码遮罩，录屏时余额与二维码保持可见 | `CampusCardResponseParserTests` 3 项覆盖余额、二维码和失败响应；付款码 UI 回归见 `E-20260715-02`；测试二维码为确定性非生产 fixture；Commits `85959a6`、`feb82b8`、`7907702`、`eae0cd8` | 2026-07-15 |
| PAY-01 | 校园卡充值 | `main/CardBalanceDeposit.kt`、`CardBalanceDepositViewModel.kt` | `Features/Payments/` | P5 / CARD-01、D-005 | 阻塞 | 金额校验、幂等订单、银行卡/支付宝选择、第三方返回与服务端对账状态机、取消/超时/未知状态和未安装降级已实现；生产默认使用不扣款的安全阻断网关，不复制 Android 剪贴板隐私缺陷 | `PaymentTests` 17 项共享覆盖；iOS 正常/弹窗/成功 Mock 截图和 macOS CI 见 `E-20260715-02`；解除条件是服务端签名网关、凭据轮换和受控支付验收 | 2026-07-15 |
| PAY-02 | 浴室缴费 | `main/BathroomDeposit.kt`、`BathroomDepositViewModel.kt` | `Features/Payments/` | P5 / CARD-01、D-005 | 阻塞 | 浴室选择、11 位手机号查询、金额、仅内存六位支付密码、服务端确认后成功及失败/取消/超时恢复均已实现；未确认结果保持待对账 | `PaymentTests` 17 项共享覆盖；iOS 正常/密码弹窗/成功 Mock 截图和 macOS CI 见 `E-20260715-02`；解除条件同 PAY-01，并需授权浴室账户 | 2026-07-15 |
| PAY-03 | 电控缴费 | `main/ElectricityDeposit.kt`、`ElectricityDepositViewModel.kt` | `Features/Payments/` | P5 / CARD-01、D-005 | 阻塞 | 校区→楼栋→楼层→房间级联、余额/累计充值、金额、仅内存六位密码和服务端结果核验已实现；无完整请求体或签名日志 | `PaymentTests` 17 项共享覆盖；iOS 正常/密码弹窗/成功 Mock 截图和 macOS CI 见 `E-20260715-02`；解除条件同 PAY-01，并需授权房间/电表 | 2026-07-15 |
| INFO-01 | 校历 | `main/SchoolCalendar.kt`、`sdk/RustSDK.kt` | `Features/SchoolCalendar/` | P4 | 已完成 | 下载、缓存、缩放、PhotoKit 保存照片及权限降级完整；黑色全屏、校历居中、右下保存/退出与加载/错误态按 Android 重做 | `SchoolCalendarRepositoryTests` 5 项覆盖缓存、回退、损坏恢复与照片保存 adapter；校历 UI 见 `E-20260714-01`，最终 device/权限文案编译见 `E-20260715-04` | 2026-07-15 |
| INFO-02 | 电话本 | `main/PhoneBook.kt`、`TelDirectoryViewModel.kt`、`data/model/Tel.kt` | `Features/PhoneBook/` | P4 | 已完成 | 本地分类、搜索、校区号码和拨号确认完整；Android 标题/搜索、横向分类胶囊、列表密度和拨号对话框已重做 | `PhoneBookTests` 4 项覆盖目录、搜索和安全拨号 URL；电话本双端证据见 `E-20260714-01`；Commits `6a84c55`、`c40eb24`、`6561f25` | 2026-07-14 |
| INFO-03 | 天气 | `main/Weather.kt`、`WeatherViewModel.kt`、`data/weather/*` | `Features/Weather/` | P4 | 已完成 | 天气页首入 GPS、拒绝后 IP 降级、城市搜索、首页显示开关、实况、预报、小时、AQI、生活指数和账号隔离缓存完整；Android 标题/搜索/卡片/设置面板保持一致 | `WeatherRepositoryTests` 7 项覆盖解析、首入定位、三类查询、缓存隔离、偏好和拒绝降级；UI 见 `E-20260714-01`，最终复验见 `E-20260715-04` | 2026-07-15 |
| CONTENT-01 | 失物招领只读 | `main/LostFound.kt`、`LostFoundViewModel.kt` | `Features/LostFound/` | P4 / AUTH-02 | 已完成 | 认证请求层复用 Rust 会话 Cookie 并识别 401/403/登录重定向；真实 campus/type/list 端点、失物/寻物双列表、校区/类型/全文筛选、分页、详情和受控图片加载完整 | `LostFoundTests` 的契约解码、跨字段筛选和无重复分页 3 项及双端列表/详情/三态截图在 `E-20260715-01` 通过；Commits `d8516f2`、`7b688b7`、`aeda622`、`1c0f950` | 2026-07-15 |
| CONTENT-02 | 失物发布与删除 | 同上、`crawler/model/adwnh/*` | `Features/LostFound/Compose/` | P5 / CONTENT-01 | 已完成 | 真实发布/删除端点只在服务端确认成功后改变 UI；所有权由可靠用户标识判定，“我的帖子”、字段校验和失败提示完整；未确认的图片上传能力不伪造 | `LostFoundTests` 的草稿校验、远端确认后可见、拒绝删除他人/成功删除本人 3 项及双端 60% 发布面板在 `E-20260715-01` 通过；Commits `d8516f2`、`aeda622`、`77a5ae5` | 2026-07-15 |
| CONTENT-03 | 学习资料浏览与下载 | `main/Repository*.kt`、`RepositoryViewModel.kt`、`data/repository/*` | `Features/Repository/` | P4 | 已完成 | 仓库/目录浏览、缓存、URLSession 临时文件流式落盘、进度、Quick Look/系统分享、单个和批量删除完整；Android 页面结构已重做 | `StudyRepositoryServiceTests` 6 项覆盖六仓契约、目录缓存、双源下载进度和删除；UI 见 `E-20260714-01`，最终 device 构建见 `E-20260715-04` | 2026-07-15 |
| PREF-01 | 设置、偏好、关于、许可证与贡献者 | `Settings.kt`、`settings/*`、`PreferencesViewModel.kt`、`LicenseViewModel.kt` | `Features/Settings/` | P1→P7 | 已完成 | 设置首页及通知、通知增强、系统 Liquid Glass 状态说明、Android 主题色四个偏好块保持同序；原无效的自绘底栏玻璃开关改为“跟随 iOS 系统”，避免暗示 App 能关闭系统 Tab Bar 材质；贡献名单、可见及隐藏 Debug、意见反馈和偏好持久化完整 | `AndroidThemeColorTests` 3 项、`ContributorsCatalogTests` 3 项、`AndroidParityIconTests` 1 项；原设置/偏好证据见 `E-20260714-01`～`03`，本轮文案与系统底栏关联见 `E-20260716-01` | 2026-07-16 |
| SYS-01 | WidgetKit 课表组件 | `appwidget/ScheduleAppWidget.kt`、`WidgetUpdateScheduler.kt` | Widget Extension | P6 / SCH-01 | 已完成 | App Group 原子共享全学期课表快照，WidgetKit 小/中/大尺寸、未登录/过期/空状态、跨周 30 分钟时间线、当前/下一节强调和点击回 App 完整 | `ScheduleWidgetSnapshotTests` 5 项含跨周推进；原 Widget 证据见 `E-20260715-01`，最终 Extension/IPA/Archive 见 `E-20260715-04` | 2026-07-15 |
| SYS-02 | 课程提醒与可选 Live Activity | `notification/CourseReminder*`、`CourseLiveUpdateHelper.kt` | `Core/Notifications/`、ActivityKit Extension | P6 / SCH-01 | 已完成 | UserNotifications 授权、提前 10 分钟、未来三周过滤、时区日期、前台/时区变化重排完整；ActivityKit 锁屏与灵动岛下一节课倒计时、设置开关和 Debug 测试入口完整 | `CourseReminderPlannerTests` 含跨周规划，ActivityKit App/Widget device 编译、IPA/Archive 与最终 CI 见 `E-20260715-04`；物理机投递保留为部署回归 | 2026-07-15 |
| OPS-01 | 灰度、诊断、隐私、CI 与发布 | `data/gray/*`、`settings/Debug.kt`、`.github/workflows/ci.yaml` | `Core/Operations/`、`.github/workflows/` | P0→P7 | 已完成 | Android 同算法灰度、本地兜底/Debug 覆盖、可见及隐藏兼容入口、不可逆账号摘要、脱敏日志、隐私清单/数据地图、敏感信息扫描、Release Archive、未签名 IPA 与 Personal Team 发布清单完整；第三方崩溃/统计/广告保持关闭 | `ReleaseOperationsTests` 8 项、设置→Debug UI 路径、Archive/IPA/全套 macOS CI 见 `E-20260715-02`；物理机 7 天签名是部署回归，不冒充已执行证据；Commits `c091244`、`edfd219` | 2026-07-15 |

### 8.1 全量复查收口（2026-07-15）

下表记录 2026-07-15 全量复查范围；该轮证据见 `E-20260715-04`。2026-07-16 原生系统 Tab Bar 修复已完成，证据单独见 `E-20260716-01`。

| 覆盖切片 | 状态 | 本轮补齐内容 | 预定自动验证 |
| --- | --- | --- | --- |
| APP-01、PREF-01、OPS-01 | 已完成 | 系统 `TabView`/`UITabBar`、UIKit 原生导航栏、原生左边缘返回、iOS 26 内容区域返回；完整 Debug、更新、反馈、许可证、主题与 Dynamic Type | `XCUIElementTypeTabBar`、原生导航 UI 手势、Debug 路由、更新语义、图标与主题单测、全路径 UI；本轮底栏证据见 `E-20260716-01` |
| AUTH-02、CONTENT-01 | 已完成 | Cookie 父域/Path/Secure/HttpOnly、响应 Cookie 持久化、401/403/登录重定向自动续期；网络/5xx 不误退出且保留离线缓存；续期凭据被拒时清理失效材料并由根导航回到登录页 | Cookie 匹配/响应/重试契约、离线恢复、续期拒绝与会话测试 |
| SCH-01、SCH-02、HOME-01 | 已完成 | 当前学期按真实日期推导、真实下学期 SDK 接口、重叠课程分栏；首页课程入口、拖放编辑、灰度门、账号隔离布局和已放工具过滤 | Semester、布局、课表 Repository/UI 回归；Rust server feature 编译 |
| ACA-01、ACA-02、ACA-03 | 已完成 | 多学籍切换、真实学期排名、账号隔离成绩/考试缓存；空闲教室默认全楼栋与日期约束 | Rust 多学籍/排名解析、Swift 成绩/考试/空教室单测与全状态 UI |
| CARD-01、INFO-01、INFO-03、CONTENT-03 | 已完成 | 校园卡缓存键改为不可逆账号摘要，二维码显示时亮度提升并恢复；天气页首次进入先请求定位、拒绝后降级 IP，首页显示开关生效；校历用 PhotoKit 真正保存照片；学习资料流式临时文件落盘与系统分享 | 账号摘要、定位优先/拒绝降级、PhotoKit adapter、现有服务契约/缓存测试、Release device 构建 |
| SYS-01、SYS-02 | 已完成 | Widget 随跨周时间线推进课程与周次；未来三周通知重排；前台/时区变化维护；ActivityKit 锁屏与灵动岛实现 | 跨周 Widget/提醒单测、Widget Extension 编译、IPA/Archive 扩展检查 |

外部支付网关仍然是唯一不能由客户端代码闭环的产品阻断；生产支付目录不再回退演示数据，待 D-005 解除后再做真实扣款和对账验收。

## 9. 平台差异与已知 Android 缺口

| 项目 | Android 现状 | iOS 迁移决策 |
| --- | --- | --- |
| 首登流程 | `Setup.kt` 的登录路由已注释但仍导航，主登录当前直接进入 Home，`Info.kt` 非正常必经链路 | Root 使用单一版本化协议 gate；必要说明确认后才进入 App Shell；拒绝保持在当前页，设置中可再次查看和撤回，不翻译遗留导航 |
| 首启商业弹窗 | Android 将“商业合作”与两份必要说明同等处理，拒绝即退出 | iOS 将其作为自愿阅读的社区说明，不保存强制同意，也不阻塞核心功能 |
| 返回导航 | Android 使用 Compose 顶栏与系统返回分发 | iOS 详情页保留 Android 同款内容布局，同时恢复 `UINavigationController` 原生导航栏与系统返回按钮；不自定义转场 delegate，仅启用系统拥有的左边缘 `interactivePopGestureRecognizer`，iOS 26+ 同时启用由 UIKit 协调滚动/横向手势冲突的 `interactiveContentPopGestureRecognizer` |
| 首启声明/隐私正文 | Android 固定 SHA 的正文含“不会收集/存储”“未实现上传”等绝对陈述，与 iOS 已实现的校园请求、天气网络查询及未来真实数据处理范围不完全相符 | 对话框几何、标题、控件完全对齐；正文按 D-009 使用与实际处理一致的开发期说明，不复制失真陈述。AUTH-01 功能/UI 验收不再被阻塞，正式法律文本仍是 P7 发布门槛 |
| 首启转场残影 | Android 自动截图中活动弹窗后方可见上一层非活动弹窗的淡化残影 | 只对齐活动弹窗的内容、几何与遮罩；不复制非活动层未及时移除的转场缺陷 |
| 密码与会话 | 密码、Rust Cookie、业务数据会进入 MMKV/Rust KV；Cookie 另有持久化副本 | `CredentialStore` / `CampusSessionStore` 将密码与 Cookie 限定到 ThisDeviceOnly Keychain 并按学号隔离；Rust `persist_session=0` 明确禁止 Cookie 写入 GuiXu，初始化时先清空旧内存 Cookie 再加载 Keychain seed；GuiXu 只保存非敏感业务缓存 |
| Rust 复用 | Android 使用 `.so`、JNI 和本地 HTTP 服务 | Apple Simulator/device staticlib 已验证；C ABI 管生命周期、GuiXu 初始化及 KV 增删查清，随机 token 保护的 loopback 服务承载现有 SDK 路由，Swift 使用可注入 `URLSession`，ATS 例外仅限 localhost |
| 会话续期 | 302 检测、全局状态、同步锁及本地密码重登 | 使用 `AuthSession` actor 统一刷新、并发去重、过期通知与显式重新认证 |
| 网络安全 | 存在全局明文流量配置 | 默认严格 ATS；仅对经论证的本地通信做最小例外 |
| 客户端凭据 | Android 支付链存在硬编码客户端凭据/签名材料及敏感日志 | 不记录具体值；先轮换并迁到服务端签名/安全配置，清理敏感日志，否则支付阻塞 |
| 支付生产边界 | Android 客户端直接生成/提交签名请求，并在电控链路输出可能包含业务参数的调试日志 | iOS 仓库不包含签名材料，生产默认 `SafetyBlockedPaymentGateway` 明确拒绝扣款；只在 `--demo-session` 使用不可支付的确定性 Mock。服务端签名网关和受控测试环境到位前，三类支付保持“阻塞” |
| 校园卡支付宝引导 | Android 将本地姓名/学号复制到剪贴板后跳转支付宝校园卡小程序 | iOS 保持同信息与支付方式弹窗，但不把身份信息写入系统剪贴板；只尝试白名单 URL Scheme，未安装时保留页面并明确提示，回到 App 后必须向服务端对账 |
| 支付密码与待处理订单 | Android 三类支付分别实现，失败/日志/恢复语义不完全一致 | iOS 使用统一状态机；六位密码仅存于提交调用栈并立即清空，持久化只保存不含个人信息的功能类型与订单号；重复提交、取消、超时、未知状态和外部 App 返回均有测试 |
| 灰度身份 | Android 支持服务端灰度、本地 SHA-256 分桶和 Debug 覆盖 | iOS 保持相同 SHA-256 分桶向量、开关和 Debug 页面；请求前先哈希账号，游客不生成可跨启动跟踪的设备标识，远端失败回退本地结果 |
| 课表 | 主要功能成熟；当前时间指示线有显式 TODO | 先完成行为对齐；时间线作为独立增强项，不阻塞首个课表切片 |
| 课程数据格式 | 旧 `Course` 缓存把 weekday/周次/节次保存为字符串，新教务 Activity 使用整数和 `weekIndexes`；空 weekIndexes 的 Activity 会被丢弃 | iOS `Course` 解码同时接受字符串和整数；存在 `weekIndexes` 时以去重排序后的精确周为准，否则兼容旧起止周范围；畸形数据不触发强制转换崩溃 |
| 课表缓存隔离 | 大部分当前学期缓存带用户前缀，但 `next.schedule` 仍是共享键 | iOS 持久化协议从入口要求 `UserScopedStore`，当前/下一学期均不得绕过用户命名空间；GuiXu 物理键再做 SHA-256，数据库文件不出现学号或业务键明文；旧 UserDefaults/文件缓存只迁移一次 |
| Debug 入口 | App 卡片连续点击 8 次后进入 Debug | 按用户显式要求，设置首页直接显示 `Debug` 行；原 8 次点击路径继续保留，页面内容与 Android 对齐 |
| 电话本 | Android 使用 `ACTION_DIAL`，双校区号码先弹窗选择；号码注释来自 2025 新生手册并含 2026 年 3 月更新 | iOS 保留 9 类 57 个条目及来源说明，统一补 0551 区号；所有号码（含单号码）先由确认菜单选择，再交给系统电话应用，不申请通讯录权限 |
| 校历 | Android 下载 `openahu.org/download/xiaoli.jpg` 到应用目录，支持手势缩放并可申请权限保存相册 | iOS 校验图片签名并原子缓存，损坏缓存自动清理、刷新失败显示旧缓存；使用 1–5 倍原生手势、Quick Look 和 ShareLink，不写相册，因此无需照片权限且拒绝权限时无功能损失 |
| 学习资料 | Android 通过 GitHub Contents API 浏览 6 个学院仓库，jsDelivr/Raw 下载到外部应用目录，再以 Intent 打开 | iOS 保持同一仓库清单和分支，目录按仓库/路径缓存；文件流式下载到 Application Support、文件名哈希化，使用 Quick Look/ShareLink；公开 GitHub 限流或断网时回退已访问目录和已下载文件 |
| 失物招领 | 图片上传未实现；发布/删除可能提前提示成功；“我的帖子”只过滤当前已加载数据 | 不复制缺陷；服务端确认后更新 UI，“我的帖子”使用可靠查询/分页语义 |
| 失物认证请求 | Android 使用 AutoLoginInterceptor/TokenAuthenticator 自动带会话并处理登录跳转 | iOS 认证 Web 客户端只向校园域发送内存 Cookie，显式识别 401/403 和登录重定向；失败不伪装为空列表或成功 |
| 课表桌面组件 | Android 使用 Glance/定时更新 | iOS 使用 App Group 只读快照和 WidgetKit 时间线，支持小/中/大尺寸及深链；系统可能延迟刷新，不承诺 Android 调度时点 |
| 课程提醒 | Android 使用 AlarmManager/BootReceiver 和厂商通知能力 | iOS 使用 UserNotifications，按当前周和时区提前 10 分钟重排；系统可延迟投递，Live Activity 是独立可选增强，不绑定普通提醒完成 |
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

## 10. 安全门槛

以下条件在支付或真实账号广泛测试前必须完成：

- [ ] 确认并轮换 Android 中已暴露的客户端凭据和支付签名材料；iOS 仓库不得复制其值。
- [ ] 将签名或不可公开的业务能力迁到受控服务端，客户端只持有最小权限配置。
- [x] 密码、Token、Cookie 全部进入 Keychain；缓存清理、退出登录和账号切换行为有测试。
- [x] 建立脱敏日志策略，禁止输出 Cookie、Token、密码、完整请求体和可识别账号信息。
- [x] `AuthSession` 统一处理 Cookie、Token、刷新、并发去重和过期事件。
- [x] 默认启用 ATS，仅为必要域名或经论证的本地通信配置最小例外。
- [x] 支付状态机覆盖重复提交、超时、取消、第三方 App 返回、服务端未知状态和结果对账。
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
| R-001 | Rust crate 的 Apple target、FFI 和依赖兼容性未知 | 高 | 固定子模块已完成 Simulator/device staticlib、C ABI 生命周期和 Swift 请求链路验证；持续由两条 macOS workflow 防回归 | 已解除 |
| R-002 | 登录依赖多个校园系统、Cookie 同步、验证码/OCR 与页面解析 | 高 | 已固化脱敏 fixture/契约，统一 AuthSession、Rust Cookie 同步、过期重登和可观测错误均通过 CI；继续用授权账号监测外部页面变化 | 已缓解 |
| R-003 | 客户端存在凭据、支付签名与敏感日志风险 | 严重 | 轮换、服务端化、日志审计完成前阻塞支付 | 阻塞支付 |
| R-004 | 支付缺少稳定沙箱，真实验证可能涉及资金 | 严重 | 授权测试账号、小额边界、幂等和结果对账方案齐备 | 阻塞支付 |
| R-005 | 当前 Windows 环境无法运行 Xcode | 高 | macOS 26/Xcode 26.5 Simulator 全测和未签名 iphoneos 构建持续通过；仅 Personal Team 物理机回归仍由用户执行 | 已缓解 |
| R-006 | 历史 Android 截图与固定 SHA 不一致，且原环境无 Android Emulator 基线 | 高 | 已建立固定 SHA 的 Android CI/UI pipeline，并与 iPhone 13 Pro Simulator 按 1170×2532、43 个同状态画面完成逐屏终验 | 已解除 |
| R-007 | 核心 Android 业务缺少自动化测试 | 高 | iOS 迁移先补 fixture、解析、周次、会话和支付状态机测试 | 开放 |
| R-008 | 外部校园页面、第三方 API 与 App Store 政策可能变化 | 高 | 域隔离、契约监控、失败降级、隐私/审核复查 | 开放 |

## 13. 下一工作包

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

### P5-P7-W2：100% 收口与外部解除条件

- [x] PAY-01～03 完成统一金额/密码校验、幂等订单、超时/取消/未知状态、第三方返回和服务端对账客户端状态机。
- [x] 三类支付完成 Android 对齐入口、表单、确认弹窗、Mock 成功态与专项单元/UI 测试；生产构建默认安全拒绝扣款。
- [x] OPS-01 完成 Android 同算法灰度、Debug 诊断、账号摘要、脱敏日志、隐私清单、数据地图、敏感信息扫描、Release Archive 和 Personal Team 发布手册。
- [x] GitHub Actions 生成含 Widget 与双隐私清单的未签名 IPA/Archive；仓库和产物不含签名证书、描述文件或 Apple ID。
- [ ] 支付负责人轮换 Android 已暴露材料，并提供受控的服务端签名网关 URL 与最小权限客户端鉴权方式。
- [ ] 为校园卡、浴室和电控分别提供可审计的测试账号/房间或明确授权的小额真实环境，并完成成功、拒绝、超时、重复提交、第三方返回和对账验收。
- [x] 原生 Tab Bar 的 APP-01 已由 `E-20260716-01` 恢复“已完成”，严格完成度回到 20 / 23（87.0%）；支付解除条件完成后再将 PAY-01～03 逐项推进，不以 Mock 或未扣款 UI 伪造 100%。

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
