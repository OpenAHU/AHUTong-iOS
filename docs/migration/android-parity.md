# Android → iOS 迁移长期路线图

> 本文件是 iOS 迁移任务的唯一进度源。每完成一个可独立验收的功能切片，必须在同一次改动中更新状态、验证证据、关联提交和变更日志。

## 当前摘要

| 项目 | 当前值 |
| --- | --- |
| 总体状态 | 当前 iOS 范围为 25 个切片，教学评价已按产品决策整体移除；余下 25 / 25 个切片均有客户端实现，五个支付切片仍待物理 iPhone 授权账号验收 |
| 当前里程碑 | iOS 登录为官方可见 WebView 首登和前台隐藏 WebView 校园服务认证；隐私 v6 保留 OCR 与学校邮箱说明，新增经过过滤的 Sentry 诊断用途与撤回控制，接受或拒绝隐私后仍可选择只含课表与设置的体验账户 |
| 当前焦点 | 当前未提交背景/原生导航/扫码/天气切片见 E-20261029-01/02/03；本轮审计包体与 Android/iOS Sentry 配置，按用户选择不查询线上事件，必吃榜窗口详情改为原生半屏/全屏 sheet，见 E-20261029-04 |
| 下一步 | 本机 iPhone 17 Pro 验证透明课表、背景和天气；真实相机识别、美团/学习通/淘宝协议及倾斜视差仍需物理设备体验。版本保持1.0.6（15），本轮不推送或触发Actions；Widget共同App Group授权仍按用户决定延期 |
| 客户端实现覆盖 | 历史固定范围 25 / 25；本轮新增的培养方案、账单/统计与必吃榜独立列示，不将历史分母当作最新 Android 全量覆盖率 |
| Android 生产行为对齐 | 历史固定基线、既定 iOS 范围为 25 / 25；不代表当前 Android master 全量对齐。全量源码审计基线 `680abc29`（3.4.7-beta1）见 §9.2；必吃榜追加对照最新 master/develop `90a0fdc`（3.4.7），见 E-20261027-07。本分支已补培养方案、只读账单/基础统计、考勤和必吃榜个人记录；考勤、个人记录与真实贡献仍待授权账号验收，必吃榜公开查询已验 |
| 严格完成定义 | 12 / 25（48.0%）；按当前主矩阵“已完成”逐行统计，修正此前摘要 14 与矩阵 13 不一致；本轮 OPS-01 因安装回归重开为待验证，SYS-01 仍待真机验证 |
| 当前维护 | 工作副本 `/Users/himekawa/Projects/AHUTong/iOS`，本轮分支 `codex/ios-wallpaper-native-navigation`，基于已推送1.0.6的 `7fc7ca1`；不改AIO gitlink。保留四分类工具UI、8槽位/17工具（新增身份码）、服务器OCR及原生产标识 |
| 最近更新 | 2026-10-29 |

## 1. 目标与边界

### 1.1 长期目标

在 iOS 上以 Swift 和 SwiftUI 重建 AHUTong 的核心体验，使登录、课表、首页、学业查询、校园服务及系统集成达到可验证的 Android 行为对齐，同时遵循 iOS 的交互、安全、隐私和发布规则。

迁移以固定 Android SHA 的代码与该版本实际渲染结果为唯一产品基准。业务实现不逐行翻译 Kotlin，但用户可见 UI 必须逐屏、逐状态对齐 Android；Android 中已知的安全问题、无效设置、提前提示成功等缺陷不得复制到 iOS。

### 1.2 当前范围

- 应用启动、协议确认、登录、会话恢复与退出。
- 四个主入口：主页、课表、小工具、设置。
- 课表、成绩、考试、空闲教室、校历和电话本；本科培养方案完成情况。
- 校园卡余额与付款码、只读账单及消费统计、校园卡充值、招商银行充值、浴室缴费、电控缴费和网费充值。
- 天气、失物招领、学习资料浏览/Markdown 阅读/下载管理；教务考勤、必吃榜/个人记录与自愿贡献。
- 首页自定义、全局照片背景/遮罩/主题取色与可选动态视差、课表桌面组件、课程提醒与可选 Live Activity。
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
2. 页面信息架构、组件类型、内容顺序、中文文案、图标语义、颜色、字号/字重、圆角、阴影、间距、留白、对齐、卡片尺寸、列表密度、底栏和顶部栏必须与 Android 保持一致；第 8～16 条记录的用户显式覆盖除外。
3. 正常、加载、空数据、错误、弹窗、菜单、搜索、展开/收起、刷新和权限降级等可见状态都必须逐一对齐；不能只对齐首屏静态状态。
4. iOS 只允许保留系统强制差异：安全区、Home Indicator、系统权限弹窗、系统返回手势、拨号/分享/Quick Look 等系统控制器。差异必须限制在系统边界内，并记录在平台差异表中。
5. 在未被用户原生 UI 要求覆盖的页面，SwiftUI 使用等价实现对齐 Android 外观；需要时应以自定义组件复现 Compose 布局。四入口底栏按第 8 条使用系统 `TabView`，设置表单与课表弹层按第 11 条优先使用系统组件；小工具列表、搜索和引导按第 16 条使用原生组件。
6. 每个页面完成前必须保存同一设备尺寸、同一数据状态的 Android 与 iOS 截图，检查关键几何尺寸与颜色；主要页面必须有 UI 测试覆盖可见文案、入口和交互状态。
7. 本约束追溯适用于此前已标记完成的 APP-01、AUTH-01、INFO-01、INFO-02、INFO-03、CONTENT-03；这些切片在 UI 复验通过前统一回到“实现中”。
8. 2026-07-16 用户进一步明确四入口必须使用 iOS 原生底部导航，而非仅在自绘容器上调用 Liquid Glass API。根容器必须使用系统 `TabView`/`UITabBar`，iOS 26+ 的 Liquid Glass、折射、触控、辅助功能和后续系统演进全部交给系统；禁止自绘 `HStack + Button` 冒充原生 Tab Bar。Liquid Glass 默认启用，设置页不得提供开关、关闭路径或单独说明入口。入口顺序、图标、中文文案和选中语义仍与 Android 一致。
9. 2026-09-23 用户要求彻底删除 iOS Debug 页面与 App 信息卡隐藏入口；设置首页使用真实 App 图标。2026-09-24 用户进一步明确账户信息与真实账号登录保留在设置首页，仅隐私选择及登录偏好进入偏好设置。
10. 设置域所有可点击行必须在跳转或执行前提供可感知的按压态；iOS 使用轻触觉、明暗高亮和短缩放补足交互反馈，开启“减弱动态效果”时禁用缩放但不得移除非动态反馈。静态布局仍以 Android 为准。
11. 2026-10-19 用户进一步要求更多 iOS 原生 UI，明确指出设置通知按钮卡顿、iOS 26+ 课表设置缺少玻璃材质。设置首页/偏好使用系统 `Form`、`NavigationLink` 和真实 `Toggle`；系统开关保留原生操作与反馈，导航/动作行继续保留轻触觉及按压反馈。课表设置采用系统半高 sheet 和工具栏，不用实色背景覆盖系统 Liquid Glass；不提供玻璃开关。此条覆盖对应页面的 Android 静态组件复刻限制。
12. 2026-10-19 用户要求课表、小工具右上角按钮使用原生材质；进一步明确课表三个动作共用一块玻璃背景。课表采用原生 `ControlGroup`，iOS 26+ 共享系统 Liquid Glass 胶囊，iOS 17–25 共享系统 Material 胶囊；小工具独立编辑按钮保留系统玻璃圆钮。每个动作触控范围至少 44pt，保留图标、功能和 VoiceOver 名称，不新增材质开关。课程详情按内容收紧高度，地点/教师不被分隔线撑高，周次完整换行，大字体可滚动。空昵称贡献者的年级按 Android 记录为 22级。
13. 2026-10-20 用户明确要求电话本使用原生 UI：使用系统 List、Picker、searchable、confirmationDialog 和导航栏，覆盖本页的 Android 外观复刻限制；保留原有条目、搜索与拨号确认，不复制自绘弹窗布局。

14. 2026-10-22 用户要求极光蓝替代默认紫，原紫命名为“鸢尾紫”；总览中的非本周课程使用灰色且与当周卡片圆角一致。校园邮箱尽量使用系统 List / Form / Menu / Toolbar，官方邮箱页仅作为富文本及复杂附件回退。点击小工具和设置均回到根页，包含外部跳转后的切换。
15. 2026-10-22 用户要求课表设置新增默认关闭的“每周开始于周日”，开启后按周日—周六连续日期展示，课程实际日期保持不变。总览非本周卡片进一步使用浅中性灰底与自适应灰色文字。

16. 2026-10-26 用户要求小工具页更多原生体验并保持代码简洁，后否定系统 List 并提供 Android 参考图。最终采用缴费充值、学业教务、校园生活、学习工具四分类标题与双列浅底描边卡片；系统 searchable、NavigationLink、Toolbar、TabView 和 Widget Form 保留。卡片整面可点，复用轻触觉、高亮及短缩放；减弱动态效果时禁用缩放。优先保留分类及正常字号，允许滚动；所有已有工具继续可达，首页已固定的工具仍显示。Swift 单元测试上限 500，UI/Python/Rust 不计入；按风险选择独立用例并删除有依据的冗余或过期测试，不合并场景或跳过规避。

17. 2026-10-27 用户进一步明确各个小工具使用原生 UI，同时大致设计和页面布局尽量保持原样。保留卡片、信息顺序、筛选/结果区及专用内容布局，系统组件替换通用搜索、菜单、按钮、导航和弹层；不将不同工具统一重排为整页分组列表。首页保留 8 个位置，16 种工具全部可选。

18. 2026-10-27 用户明确移除 iOS 灰度：首页长按编辑、拖放和小工具页编辑入口默认提供，不依赖远端策略、分桶或测试启动参数；不得自行重新引入灰度控制。

19. 2026-10-29 用户要求子页面持续显示系统底栏；课表周选择器略上移且不能缩窄可视范围，右侧三个动作直接显示并使用系统工具栏。全局背景对齐 Android 的照片、0–100%亮暗遮罩和主题取色；增加可选 UIKit 动态视差，不引入关闭玻璃开关。此条覆盖第12条的自定义顶栏容器，见 E-20261029-01。

## 2. 固定基线

| 仓库 | 基线 | 说明 |
| --- | --- | --- |
| Android 2026-10-29 背景参考 | `c627dc28dec41ab1032191e7b39a872742de8c00` | master，3.4.8-beta1；只读对照 HomeBackgroundStore.kt / ThemeLab.kt；不迁移关闭玻璃偏好 |
| Android 2026-10-26 最新源码审计 | `680abc29e2df7da0c2c650e2f88c8355327bc01d` | master/develop 同尖端，3.4.7-beta1；只读源码审计，不代表 Android 运行验收；详见 §9.2 |
| iOS 2026-10-26 上游 | main `9e8478a` / develop `f7a79e0` | 仅 fetch 和读取；当前开发仍在既有维护分支，不推送/合并、不触发 Actions |
| iOS 本轮原生 UI / 校园码基线 | `7897a54e92a929814d9a74776eab8d423604a842` | 官方 main；1.0.2 集成后起点 |
| Android 2026-10-22 邮箱参考 | `b6961a3aee85da67cfc5300dd8ed829da2a123a2` | 官方 master（3.4.5），仅只读对照；邮箱协议/会话的主体与既有 `595e63c` 一致，另核对下载取消与 ViewModel 后台调度修复 |
| iOS 2026-10-22 维护基线 | `6b843b7e7db66087304ae9186a9e9cb3b1adb8c1` | 最新 main，PR #7–#9 已合入；本轮不改 AIO gitlink |
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
| D-008 | 开发期真机分发与签名 | 开发期侧载，正式签名待定 | CI 生成待重签 IPA；Apple ID 不进入仓库或 GitHub Secrets。1.0.2（4）起用 ad-hoc 临时签名保留共享权限声明，仍需自有团队实际授权；Personal Team 限制与 Developer Program 账号分开处理，不把账号会员身份视为 App Group 已启用，不等同于 TestFlight/App Store 发布 |
| D-007 | 崩溃上报、灰度、统计与广告方案 | 已确定当前方案 | 已集成经同意启用且严格过滤的 Sentry 原生崩溃/Widget/会话续期诊断；无日活、回放、性能或校园码最终失败采集。iOS 灰度及其账号摘要请求已移除，首页编辑默认可用（E-20261027-09）；本轮两端诊断审计见 E-20261029-04，未扩展采集范围；不集成广告 SDK |
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
| APP-01 | App Shell、四入口与统一状态 | `ui/screen/Main.kt`、`BottomNavBar.kt` | `App/`、`Core/DesignSystem/` | P1 | 已完成 | 主页/课表/小工具/设置顺序、图标、文案、选中态、Android 色板/卡片/标题/搜索组件和统一页面背景保持不变；按用户显式覆盖，底栏由系统 `TabView`/`UITabBar` 承载，iOS 26+ 自动采用系统 Liquid Glass；每个入口保留独立导航路径，按2026-10-29用户要求详情页保留系统底栏；冷启动本地会话就绪即进入首页，网络校验不阻塞开屏；最终 UI smoke 见 E-20261014-01。  2026-10-26 用户提供参考图后，小工具采用四分类标题与双列浅底描边卡片、共享按压反馈、系统搜索和原生导航，保留 16 个工具与返回语义，Widget 引导使用 Form/sheet，见 E-20261026-03。 本轮统一工具目录与目的地，首页新增身份码后为17选8，原生通用控件保留既有页面布局。 2026-10-29移除自加整页淡入；课表/小工具根页按钮组由RootView在同一次原生切换事务中更新，恢复系统玻璃过渡，导航栈与选中周保留，见E-20261029-03。 | 原双端对照见 `E-20260714-01`；系统 Tab Bar 类型、四标签、隐藏/恢复和双返回手势最终回归见 `E-20260716-01`；Commits `0a8f855`、`4bb2bab`；2026-10-14 本机 401 单测 + 2 UI 回归通过，见 `E-20261014-01`；2026-10-19 原生四标签、顺序/选中语义及无玻璃偏好入口复核见 `E-20261019-02`；本轮以 Android 实际路径修正四图标、App 图标开屏及默认动态效果，见 `E-20261019-03`  原生工具页与测试清理见 E-20261026-01。 本轮原生控件与布局边界、验证见 E-20261027-04；圆角补充见 E-20261027-05。 | 2026-10-29 |
| AUTH-01 | 启动、三份协议与首登流程 | `ui/screen/Splash.kt`、`ui/screen/setup/*` | `Features/Onboarding/` | P1 / APP-01 | 已完成 | Android 对话框几何、内容滚动区、按钮和三页标题顺序已对齐；同意状态持久化，拒绝与再次查看路径明确 | `AgreementConsentStoreTests` 3 项通过；双端首启三弹窗证据见 `E-20260714-01`；Android 非活动旧弹窗残影不复制，见第 9 节；Commits `430bd45`、`d15a207`、`6561f25` | 2026-07-14 |
| AUTH-02 | 登录、会话恢复、过期重登与退出 | `Login.kt`、`LoginViewModel.kt`、`AutoLoginInterceptor.kt`、`TokenAuthenticator.kt`、`sdk/*` | `Core/Auth/`、`Core/CampusCore/`、`Core/Networking/`、`Features/Login/` | P2 / D-003、D-004 | 待真机验证 | 隐私 v4 同意后以官方可见 WebView 首登，也可点“暂不登录”进入体验账户并跨启动保持；账密/Cookie 只入 ThisDeviceOnly Keychain；教务过期时前台隐藏 WebView single-flight 续期。ADWMH 首次与后续均在前台隐藏 WebView 建立校方会话，即使没有历史 Cookie 也以同域原生 GET 获取验证码并接收新会话 Cookie，只将图片发往 `https://openahu.org/ocr/captcha` 识别并用同一 `/user/login` 续期，失败提示重试，不打开第二登录页。Keychain 会话快照统一使用 SDK 的扁平 Cookie 列表，仅在识别为原生 NDJSON 且转换非空时迁移旧 Cookie 存档，离线缓存不被空数组覆盖；写请求不重放；隐藏续期失败暂显示脱敏阶段 Toast；本地 Cookie 初始化后先开放缓存身份，再完成网络校验；退出、重新登录和体验切换使旧校验失效，避免异步恢复旧身份；临时隐藏续期失败及重复过期不再清理凭据，首次校验和业务读取保存轮换 Cookie，换账号隔离旧 Cookie  2026-10-26：OCR 无效结果/校方验证码拒绝最多 5 次新图挑战，10012 立即停止，校园卡总预算 90 秒；不清理教务凭据，仍待实机复验。| `CampusCardLoginClientTests` 覆盖登录字段与失败响应，`CampusSessionStoreTests` 新增旧快照迁移；373 个单元测试已通过，旧快照离线保护见 `E-20260924-01`；最终 macOS CI `35901490865` 全绿，取图修复与 OCR 诊断见 `E-20260924-02`、`E-20260924-03`；隐私 v4 与首次校园服务隐藏登录见 `E-20260924-05`（CI `35959882196` 全绿）；授权账号真机仍待验证；2026-10-14 本机 401 单测 + 2 UI 回归通过，见 `E-20261014-01`；2026-10-19 本轮维护与待验边界见 `E-20261019-01`  E-20261026-02。| 2026-10-26 |
| SCH-01 | Course 模型、周次解析、API 与离线缓存 | `data/model/Course.java`、`CurrentWeekResolver.kt`、`SdkDataSource.kt`、`AHUCache.kt` | `Core/Models/`、`Features/Schedule/Data/` | P2 / AUTH-02 | 待验证 | 真实账户保留 cache-first/refresh/stale-cache，并同步不含学号的体验课表副本；体验账户绝不请求 CampusCoreAPI，可导入最大 1 MB/500 门课程的 v1 JSON，只接受当前/下学期并原子覆盖；Widget 继续读取本地快照；只解析明确的教学周字段，拒绝学期 ID/布尔值/无效数字；按账号和学期保存周数与日期锚点，离线按周一推进。 | `ExperienceScheduleStoreTests`、拒绝隐私 UI 路径与原课表回归待 macOS CI；2026-10-14 本机 401 单测 + 2 UI 回归通过，见 `E-20261014-01` | 2026-10-14 |
| SCH-02 | 课表 UI、课程详情与设置 | `main/Schedule.kt`、`ScheduleViewModel.kt`、`main/schedule/*` | `Features/Schedule/` | P2 / SCH-01 | 已完成 | 切换 Tab 保留所选周、20 周左右分页、真实日期、单双周、重叠课程、总览、下学期、课程详情和全状态完整；新增 Android 3.2.0 同款地点缩写、周次范围及总览可读文本；日期使用同一校园日历和周数锚点；教务周次仍按周一推进；用户可开启周日开始的连续日期周视图，周日取对应实际日期的课程，学期末周日保留；总览非本周使用浅灰底和统一圆角，回到前台自动推进日期；未知周数/下学期起始日期显示占位而不伪造日期；旧请求不覆盖下学期预览。 本轮深色总览非本周背景灰阶略提亮至 0.24，浅色与卡片圆角不变。 顶部周选择与三个直接显示的动作现位于系统导航栏（ToolbarItemGroup），使用与小工具/设置相同的系统默认导航栏和滚动边缘效果；保留周圆标与原有可视范围，替代原safeAreaBar/Inset实现；按用户澄清移除课程格子底板，背景直接透出，课程卡片保留可读颜色，见 E-20261029-01/02。 | 原功能证据见 `E-20260714-01`、`E-20260717-04`、`E-20260717-06`；`ScheduleTextFormatter` 与全量回归见 `E-20260726-01`；2026-10-14 本机 401 单测 + 2 UI 回归通过，见 `E-20261014-01`；本轮周日视图与浅灰总览见 `E-20261022-02` 本轮原生控件与布局边界、验证见 E-20261027-04。 | 2026-10-29 |
| HOME-01 | 首页概览与 8 槽位自定义 | `main/Home.kt`、`main/home/*`、`DiscoveryViewModel.kt`、`data/gray/*` | `Features/Home/` | P2 / APP-01、SCH-01 | 已完成 | 今日课程时间线、天气详细/紧凑模式、8 槽位去重/增删/换位、首页编辑工具库的已放工具过滤和账号隔离持久化完整；首页和小工具页共用 16 项 ToolItem 目录与 ToolDestination 路由；保留原 homeID、8 槽位及排序；编辑时有减号和拖入移除区，长按/拖放/移除使用系统触感，移除仅影响首页摆放；紧凑天气点击只进入天气，不与课程入口冲突；首页复用账号隔离的教学周缓存，网络失败不回退为第 1 周；当前周未知时不将第 1 周课程误作今日课程。 下拉刷新对完整状态区做轻缩回弹，覆盖无课；倒计时、余额与天气温度使用原生数字过渡，见 E-20261027-08。首页编辑默认可用，灰度链路已移除，见 E-20261027-09。独立分钟时钟、教学周跨日与前台周期刷新、余额取消恢复见 E-20261027-11。 | 本轮目录迁移及 UI 验证见 E-20261027-04，首页编辑交互见 E-20261027-05/06；`HomeWidgetLayoutTests`、确定性紧凑天气 UI 专项及既有双端证据全部通过，见 `E-20260726-01`；2026-10-14 本机 401 单测 + 2 UI 回归通过，见 `E-20261014-01` | 2026-10-27 |
| ACA-01 | 成绩、多学籍、GPA 与专业排名 | `main/Grade.kt`、`GradeViewModel.kt`、`data/model/Grade*` | `Features/Grades/` | P3 / AUTH-02 | 已完成 | SDK 成绩/学籍/排名、筛选/搜索与账号隔离缓存完整；教务系统返回受限的 `gradeDetail` 时只展示清理 HTML 后的服务端文本，不再跳转教评；单学籍失败不遮蔽其他学籍；缓存刷新失败新增明确提示，本轮已在授权账号模拟器完成刷新与真实内容检查，物理机回归保留 本轮保留成绩概览和课程卡片，学籍/学期使用系统 Picker，搜索与刷新进入原生导航区域。 | gradeDetail-only 解析、HTML 清理、单学籍隔离和 Demo 学期回归保留；教评跳转于 2026-09-22 移除；2026-10-19 本轮维护与待验边界见 `E-20261019-01` 本轮原生控件与布局边界、验证见 E-20261027-04。 | 2026-10-27 |
| ACA-02 | 考试查询 | `main/Exam.kt`、`ExamViewModel.kt`、`data/model/Exam.java` | `Features/Exams/` | P3 / AUTH-02 | 已完成 | 固定 SDK `/exam`、刷新、搜索、进行中/未开始/已结束、时间、考场、座号和全状态均已实现；按 Android 3.2.0 折叠已结束考试、缩短地点并重做详情卡与加载/空状态；缓存刷新失败新增明确提示，本轮已在授权账号模拟器完成刷新与真实内容检查，物理机回归保留 本轮保留考试卡片和顺序，使用原生搜索、刷新及已结束考试 DisclosureGroup。 | 原解析修复见 `E-20260717-05`；新增显示状态与全状态 UI 复验见 `E-20260726-01`；2026-10-19 本轮维护与待验边界见 `E-20261019-01` 本轮原生控件与布局边界、验证见 E-20261027-04。 | 2026-10-27 |
| ACA-03 | 空闲教室 | `main/FreeClassroom*.kt`、`FreeClassroomViewModel.kt` | `Features/FreeClassroom/` | P3 / AUTH-02 | 已完成 | 真实楼栋 GET 与空闲列表 POST 契约、校区/楼栋多选、节次、日期范围、查询结果和加载/空/错状态完整；12 间确定性结果和卡片密度与 Android 对齐 本轮保留筛选卡片与结果区，筛选项使用原生 Toggle 按钮，查询与展开使用系统按钮。 | `FreeClassroomTests` 4 项及双端正常/加载/空/错误截图在 `E-20260715-01` 通过；Commits `d8516f2`、`1c0f950` 本轮原生控件与布局边界、验证见 E-20261027-04。 | 2026-10-27 |
| ACA-04 | 教学评价 | `main/Evaluation.kt`、`EvaluationViewModel.kt`、`EvaluationRepository.kt` | — | 不在当前 iOS 范围 | 已移除 | 首页、工具页和成绩页无入口；不包含教评模型、视图、本地预设、Token/Cookie 引导或问卷提交网络链路 | 源码与隐私数据映射静态检查；macOS/Xcode 回归待运行 | 2026-09-22 |
| CARD-01 | 校园卡余额与付款码 | `home/CampusCard.kt`、`AHURepository.kt`、`TokenManager.kt` | `Features/CampusCard/` | P4 / AUTH-02 | 待真机验证 | 首页余额静默读取；展开二维码面板自动静默读取，首次无 ADWMH Cookie 或后续过期时均使用隐藏 WebView + OCR，不弹登录页。失败状态主动重试仍只走隐藏认证；隐藏认证成功及二维码恢复后立即静默刷新余额，避免旧失败状态继续显示 `¥ --`，较早请求不得覆盖新结果；内联和全屏二维码点按强制重新取码并刷新余额；首页先预取付款码再刷新余额，慢余额请求让位且旧结果不能覆盖新状态；续期使用二维码接口验证，预取码只在内存保留 30 秒，离开页面/后台清理，显示期间按有效年龄重新获取。 | `CampusCardInteractionTests` 新增自动隐藏续期和登录后余额刷新的状态测试；二维码点击及隐藏续期阶段诊断见 `E-20260924-01`；macOS UI 复验见 CI `35901490865`，验证码取图修复见 `E-20260924-02`；首次无 Cookie 静默登录见 `E-20260924-05`（CI `35959882196` 全绿）；授权账号真机待验证；付款码优先加载及推送前本机预览见 `E-20261014-02`，410 单测 + 3 UI 全绿；2026-10-19 本轮维护与待验边界见 `E-20261019-01` | 2026-10-19 |
| PAY-01 | 校园卡充值 | `main/CardBalanceDeposit.kt`、`CardBalanceDepositViewModel.kt` | `Features/Payments/` | P5 / CARD-01、D-005 | 待真机验收 | 真实加载卡账户；银行卡按 Android `CardBalanceRequest`、`CardPayRequest` 和 ViewModel 的字段/签名规则建单、解析 `orderid`、最终提交并刷新余额。支付宝保留固定白名单小程序路径，不向剪贴板复制身份或支付信息。学校官方页面兜底已删除 | `PaymentReadOnlyDataSourceTests`、`PaymentTests`、`YCardProductionPaymentGatewayTests` 覆盖请求、固定签名向量、成功/拒绝/未知、恢复和去重；macOS CI/IPA/Archive 见 `E-20260801-02`，仅剩授权银行卡小额真机验收 | 2026-08-01 |
| PAY-02 | 浴室缴费 | `main/BathroomDeposit.kt`、`BathroomDepositViewModel.kt` | `Features/Payments/` | P5 / CARD-01、D-005 | 待真机验收 | 支持 `feeitemid=409/430` 的账户查询与 `paystep=0` 建单；解析 `orderid` 后按 Android 当前协议执行安全键盘映射，再以 `paystep=2` 提交并刷新所选浴室余额。六位原始密码只短暂位于内存并在提交/退出后清空 | URLProtocol 测试分别覆盖 409/430 完整流程、字段白名单、映射、成功与刷新；共享状态机覆盖拒绝、超时、未知、恢复和重复点击。macOS CI/IPA/Archive 见 `E-20260801-02`，仅剩授权浴室账户小额真机验收 | 2026-08-01 |
| PAY-03 | 电控缴费 | `main/ElectricityDeposit.kt`、`ElectricityDepositViewModel.kt` | `Features/Payments/` | P5 / CARD-01、D-005 | 待真机验收 | 保持 `feeitemid=488` level 0→4 级联和余额查询；按 Android 兼容签名建单，每个订单单独获取动态安全键盘材料，映射后签名提交并刷新当前房间余额。拒绝或未知结果不伪造余额刷新 | URLProtocol/固定向量测试覆盖签名、每订单动态材料、最终提交、成功刷新、拒绝、超时、未知、跨启动恢复和去重；macOS CI/IPA/Archive 见 `E-20260801-02`，仅剩授权房间小额真机验收 | 2026-08-01 |
| PAY-04 | 招商银行校园卡充值 | `main/CmbCardRecharge.kt`、`YcardApi.kt`、`PreferencesManager.kt` | `Features/Payments/CMBRechargeView.swift` | P5 / CARD-01、AUTH-02 | 待验证 | 生产校方 WebView、临时 Cookie、精确学校域和受控银行外跳保留；2026-10-26 删除 Debug 入口已不存在后不可达的 HEAD 验收分支，不保留历史报告 UI。 | 生产 URL/凭据隔离回归保留于 CMBRechargeSecurityTests；旧 HEAD 历史证据不作为当前能力，见 E-20261026-01。物理 iPhone 的网页交互/银行授权仍待验证 | 2026-10-26 |
| PAY-05 | 网费充值 | `main/NetworkRecharge.kt`、`NetworkRechargeViewModel.kt`、`YcardApi.kt` | `Features/Payments/NetworkRechargeView.swift` | P5 / AUTH-02、D-005 | 待真机验收 | 保持真实账户、套餐统计、快捷金额、服务端限额、Bearer/Cookie/Referer 与内存响应 Cookie；生产流程完成入口预热、账户查询、兼容签名建单、每订单动态安全键盘映射、最终提交和账户刷新，不再跳转学校官方页面 | `NewPaymentFeatureTests`、`YCardProductionPaymentGatewayTests` 覆盖预热/查询顺序、字段、签名、双订单动态材料隔离、成功刷新、拒绝、未知、跨启动恢复和去重；macOS CI/IPA/Archive 见 `E-20260801-02`，仅剩授权网费账户小额真机验收 | 2026-08-01 |
| INFO-01 | 校历 | `main/SchoolCalendar.kt`、`sdk/RustSDK.kt` | `Features/SchoolCalendar/` | P4 | 已完成 | 下载、缓存、缩放、PhotoKit 保存照片及权限降级完整；黑色背景、校历居中及加载/错误态保留 本轮保留校历缩放布局，保存与返回交给系统导航工具栏。 | `SchoolCalendarRepositoryTests` 5 项覆盖缓存、回退、损坏恢复与照片保存 adapter；校历 UI 见 `E-20260714-01`，最终 device/权限文案编译见 `E-20260715-04` 本轮原生控件与布局边界、验证见 E-20261027-04。 | 2026-10-27 |
| INFO-02 | 电话本 | `main/PhoneBook.kt`、`TelDirectoryViewModel.kt`、`data/model/Tel.kt` | `Features/PhoneBook/` | P4 | 已完成 | 9 类 57 个本地条目与号码保留；2026-10-20 按用户要求采用原生 List、分类 Picker、searchable 和 confirmationDialog，移除自绘撑满屏幕的校区弹窗；号码按行显示并包含区号，不申请通讯录权限 | `PhoneBookTests` 与原生交互回归见 E-20261020-02；历史条目来源见 E-20260726-01 | 2026-10-20 |
| INFO-03 | 天气 | `main/Weather.kt`、`WeatherViewModel.kt`、`data/weather/*` | `Features/Weather/` | P4 | 已完成 | 首入 GPS、拒绝后 IP 降级、城市搜索、实况/预报/小时/AQI/生活指数、账号隔离缓存及首页详细/紧凑卡完整；详情页始终显示 Android 3.2.0 全量信息，升级时删除已下线的旧六项隐藏偏好 本轮保留天气内容卡片，采用原生城市搜索、工具栏与设置 Form/sheet。 | `WeatherRepositoryTests` 的旧偏好恢复、首页卡模式及确定性 UI 覆盖全部通过，见 `E-20260726-01` 本轮原生控件与布局边界、验证见 E-20261027-04。 | 2026-10-27 |
| CONTENT-01 | 失物招领只读 | `main/LostFound.kt`、`LostFoundViewModel.kt` | `Features/LostFound/` | P4 / AUTH-02 | 待真机验证 | 自动读取真实 campus/type/list 端点时会话过期先尝试隐藏续期，失败保留缓存和重试按钮，不拉起 ADWMH 可见 WebView；只读接口接受校方 `10000` 成功码，避免把“操作成功!”当成错误；分页、筛选和详情保留 本轮保留帖子卡片、筛选/统计顺序与右下发布入口，采用原生 Picker、搜索与详情 sheet；帖子和按压高亮使用一致的 20pt 连续圆角。 | `CampusAuthenticatedClientTests` 的静默未授权与既有失物测试在 CI `35867866032` 通过；`LostFoundTests` 的 `10000` 本地夹具已在 CI `35898534602` 通过，见 `E-20260924-01`；无感续期见 `E-20260924-05`（CI `35959882196` 全绿）；真实登录联调仍依赖 AUTH-02 真机验证 本轮原生控件与布局边界、验证见 E-20261027-04。 | 2026-10-27 |
| CONTENT-02 | 失物发布与删除 | 同上、`crawler/model/adwnh/*` | `Features/LostFound/Compose/` | P5 / CONTENT-01 | 已完成 | 真实发布/删除端点只在服务端确认成功后改变 UI；会话过期显示失败与手动登录入口，不因自动重试触发 WebView 或重放写请求 本轮发布、详情和我的帖子采用系统导航与 Form/List，删除必须先确认。 | 既有所有权/发布/删除单测及 UI smoke 在 CI `35867866032` 全绿；真实登录联调仍依赖 AUTH-02 真机验证 本轮原生控件与布局边界、验证见 E-20261027-04。 | 2026-10-27 |
| CONTENT-03 | 学习资料浏览与下载 | `main/Repository*.kt`、`RepositoryViewModel.kt`、`data/repository/*` | `Features/Repository/` | P4 | 已完成 | 六学院虚拟根、面包屑、目录缓存、GitHub/代理源、Git LFS、流式下载、SHA-256/大小校验、Markdown 阅读、系统预览/分享、下载管理及自定义设置页完整；认证头不会发往非 GitHub 域 本轮保留目录/面包屑与下载布局，加速源设置及 Markdown 阅读使用原生 sheet，移除不再使用的手动 goUp。 | `StudyRepositoryServiceTests` 的路径、面包屑、LFS、下载完整性、凭据边界与 UI 覆盖全部通过，见 `E-20260726-01` 本轮原生控件与布局边界、验证见 E-20261027-04。 | 2026-10-27 |
| PREF-01 | 设置、偏好、关于、许可证与贡献者 | `Settings.kt`、`settings/*`、`PreferencesViewModel.kt`、`LicenseViewModel.kt` | `Features/Settings/` | P1→P7 | 待真机验证 | 设置首页显示真实 App 图标和账户信息卡，真实账号学号居中；登录真实账号/重新登录操作仍在首页，只有隐私开关与政策入口留在偏好设置，体验用户也可访问；Debug 页及隐藏入口已删除，贡献名单保留匿名展示名并补齐 Android `develop` 两位开发者；设置行统一轻触觉、明暗和短缩放，减弱动态效果保留非动态反馈；本轮修正偏好入口高亮越界并精简数据清理/更新文案 | 设置/体验账户 UI smoke 已更新，确认账户操作不再出现在偏好设置；CI `35901490865` 的设置 UI smoke 全绿，真机待验证；2026-10-19 本轮维护与待验边界见 `E-20261019-01`；原生入口与反馈实际模拟器复核见 `E-20261019-02`；学号居中见 E-20261027-05 | 2026-10-27 |
| SYS-01 | WidgetKit 课表组件 | `appwidget/ScheduleAppWidget.kt`、`WidgetUpdateScheduler.kt` | Widget Extension | P6 / SCH-01 | 待真机验证 | App Group 原子快照与三尺寸课表；修复仅有起止周课程被空周次过滤、缓存发布等待网络周次、测试快照覆盖真实共享目录；指引显示同步状态/数量并提供课表同步入口，保留双方唯一共同授权组适配 | 历史签名检查见 E-20261020-01；本轮契约/UI 与实机边界见 E-20261023-01，用户安装已确认缺少 App Group 授权；v2 的精确分类与团队 unknown 修复见 E-20261023-02，重新签名后的 iOS 27 显示待复验 | 2026-10-23 |
| SYS-02 | 课程提醒与可选 Live Activity | `notification/CourseReminder*`、`CourseLiveUpdateHelper.kt` | `Core/Notifications/`、ActivityKit Extension | P6 / SCH-01 | 已实现，部署边界待验 | UserNotifications 授权、提前 10 分钟、未来三周过滤、前台/时区变化维护；可选岛卡仅课前显示，上课即结束，课中/下课不创建，独立偏好、同课复用、当天、课前 10 分钟边界和圆角安全留白；后台预算不足时提前结束。当前没有 APNs，强制终止后的准点清理不作保证 | 既有提醒证据见 `E-20260715-04`；最新前台系统结束状态、后台截止消失、独立偏好与部署边界见 `E-20261019-06`；Widget device 编译、IPA 扩展检查及物理机验收分别记录；本轮 10 分钟边界、圆角布局及原生计时回归见 E-20261020-02 | 2026-10-20 |
| SYS-03 | Siri 与快捷指令（iOS 独立增强） | 不适用 | `Core/Shortcuts/`、`Core/Models/TeachingWeekParser.swift`、首页/课表快照与付款码路由 | P6 / AUTH-02、SCH-01、CARD-01 | 已实现，本地验证通过，真机待验 | 提供打开付款码和带日期参数的文字课表查询；冷/热启动与二级页面返回；体验账户拦截付款码；无课/无数据/学期越界分别返回；账号隔离、本机查询、Asia/Shanghai 日期、可靠周次锚点和中文短语资源 | `ScheduleShortcutTests` 18 项；Xcode 27.0 / iOS 26.5 专用模拟器 406 单测和 3 专项 UI 全绿，既有主界面 UI smoke 通过；iphoneos Release 和中文动作/短语元数据检查通过，见 `E-20261019-05`；物理 iPhone 侧载发现、Siri 识别/身份验证与真实付款码保留为验收边界 | 2026-10-19 |
| OPS-01 | 诊断、隐私、CI 与发布 | `data/gray/*`、`settings/Debug.kt`、`.github/workflows/ci.yaml` | `Core/Operations/`、`.github/workflows/` | P0→P7 | 待验证 | iOS 灰度及账号摘要请求已移除，首页编辑默认可用（E-20261027-09）；脱敏日志、隐私清单、敏感扫描、Release Archive、未签名 IPA 保留；CI 一次构建及五组 UI 复用保持；Debug 页面和隐藏入口已删除，支付禁写保护保持；本地修复内嵌框架签名，Release 关闭覆盖率并裁剪发布符号，新增产物门禁；Sentry 移除校园码最终失败及旧队列，当前没有日活统计；1.0.4 (8) 通用 IPA 已在本地打包，物理设备安装与共享组验证待完成 | 既有证据见 `E-20260801-01`、`E-20260801-02`；CI 分组耗时见 `E-20261020-04`；Sentry 收件/过滤见 E-20261023-02，实际符号上传见 E-20261024-01；签名修正见 E-20261025-01，体积/性能及真机边界见 E-20261025-02；原生工具页、测试审计和新包见 E-20261026-01；1.0.6本地Release/重签结构、配置和回归见 E-20261028-01，云端结果见PR #12；最新包体/两端 Sentry 采集边界审计见 E-20261029-04，不查询实时收件量 | 2026-10-29 |

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
| SCH-02 | 课表设置原生 Toggle/工具栏，课程详情按内容自适应系统 sheet，高度紧凑且完整显示周次、地点与教师 | 常规、长文本及无障碍大字体的模拟器验收见 E-20261019-11；iOS 27 无本机运行时 |
| APP-01 / SCH-02 | 课表的当前周/设置/刷新共用原生玻璃胶囊，小工具编辑保留原生材质圆钮；iOS 17–25 使用系统毛玻璃 | 最低系统保持 iOS 17，见 E-20261019-10/11；编辑入口默认可用，旧灰度已按用户要求移除（E-20261027-09） |
| CARD-01 / HOME-01 | 校园码双通道恢复，12 秒传输超时、失败后重新打开/显式重试、15 秒内存复用、可插值展开高度与异步位图 | 不保证校方接口持续可用；真实扫码/长期会话仍需设备验收 |
| SYS-02 | 关闭通知零网络，开启先查权限/缓存，系统开关及时反馈并防止重复提交 | 仍为本地通知，未增加 APNs |
| HOME-01 | 本地时钟每分钟更新，进入/回前台立即校准；首页前台课表/周次按 60 秒节流周期刷新；余额收起时按 30 秒节流、每 15 秒检查，显示校园码时按 15 秒更新并随后读取余额；启用首页天气后按 10 分钟节流、随首页周期检查；下拉刷新绕过节流，课表更新发布 Widget/快捷指令快照 | 不后台轮询；慢余额请求复用，二维码优先但取消后恢复余额状态；失败保留可用缓存，见 E-20261027-11 |
| SYS-01 | AppIntentConfiguration 外观选择；小/中尺寸显示后续课程，大尺寸按星期/节次覆盖周末晚课，显示地点缩写及重叠提示 | 三尺寸深浅色布局渲染通过；模拟器可找到并添加，但原生编辑面板受无 Team ID 的临时签名限制，仍待有效重签实机验证 |
| SYS-03 | iOS 26+ 显式前台执行；补充 Siri 搜索误匹配的简洁引导，保留旧动作标识和认证要求 | 用户实机 iOS 27 手动执行成功，语音被当作网络搜索；不宣称端到端 Siri 语音已修复 |
| ACADEMIC-NEW-01 | 本科培养方案：教务原始 JS 数据安全解析、档案选择、模块/子模块、课程状态、未完成筛选、学分汇总与账号隔离缓存 | 真实登录模拟器查询成功；不含研究生 GMIS，不缓存原始 HTML/student 身份资料 |
| CARD-NEW-02 | 校园卡账单分页/类型/月及全部时间筛选/金额过滤/详情；完整范围的消费总额、逐日与商户统计 | 真实查询及统计与服务端收支汇总一致；统计任一页失败不展示部分总额，未迁移 Android 高级餐次/食堂识别 |
| MAIL-NEW-03 | 校园邮箱原生 List / Form / Menu / Toolbar；门户 SSO / WebVPN、独立 Keychain 会话、账号边界、一次只读续期，正文纯文本、附件限额和官方临时 WebView 回退；兼容官方跳转中的页面片段 | 真实复用会话和完整新 SSO 均读到 8 个文件夹、首批 30 封列表，见 E-20261022-02；真实发送/保存/移动/附件未操作，不将只读成功扩展为全部功能验收 |

| ATTENDANCE-NEW-04 | 教务考勤：ADWMH 入口/受控 SSO、内存 JWT、状态筛选、分页/刷新、详情及真实缺勤日期 | 3 项协议/边界单测和 2 项 UI 通过；真实账号记录待验，不请求照片或提交申诉，见 E-20261026-02 |
| CANTEEN-NEW-05 | 必吃榜：榜单/推荐/抽取结果共用原生底部详情 sheet（E-20261029-04），周期/校区/食堂多选、公开榜单与图表；近180天个人正餐记录、近30天逐次确认贡献和窗口补名；约3秒原生随机抽取及结果详情；右上角系统图标组、原生贡献入口及确认上传，食堂标签使用正文色、选中值使用主题色，移除常规榜单底部说明（E-20261027-12） | 公开读取已验；用户Secret已配置，1.0.5（14）已注入并安装，客户端密钥可提取；真实贡献及服务端权限待验，不等同于保密服务端凭据，见E-20261027-13；线上#146不含此密钥，Android对照与Actions审计见E-20261027-14  1.0.6（15）强制贡献配置及实际Archive校验见 E-20261028-01，真实服务写入不由自动测试执行 |
| APPEARANCE-NEW-06 | 全局自定义照片、0–100%亮暗遮罩、从背景取主题色；可选UIKit传感器视差，减弱动态效果/后台/离开页面时停用，系统材质不关闭 | 本机导入/元数据与原生UI验证见 E-20261029-01；平面照片视差不等同于系统锁屏自动景深分层，实际倾斜效果待物理机验收 |
| SCAN-NEW-07 | VisionKit系统扫一扫；白名单识别美团单车/学习通，原文编码交给对应App；雨课堂引导微信重扫 | 分类与原文/时间参数测试、模拟器入口/不可用提示；第三方iOS协议及真实相机识别待真机，不等同于签到/开锁完成，见E-20261029-02 |
| IDENTITY-NEW-08 | 菜鸟驿站身份码：淘宝固定内页优先，未装淘宝打开公开网页；列入共享ToolItem目录和首页可选库 | 保持已有homeID，17种工具/8槽位；真实淘宝登录和身份码显示待实机，见E-20261029-02 |

### 8.1 全量复查收口（2026-07-15）

下表保留 2026-07-15 全量复查及后续补记的历史范围和状态；该轮证据见 `E-20260715-04`，不作为当前验收计数。当前状态以第 8 节功能矩阵和本文摘要为准。2026-07-16 原生系统 Tab Bar 修复证据单独见 `E-20260716-01`。

| 覆盖切片 | 状态 | 本轮补齐内容 | 预定自动验证 |
| --- | --- | --- | --- |
| APP-01、PREF-01、OPS-01 | 已完成 | 系统 `TabView`/`UITabBar`、UIKit 原生导航栏、双原生返回；账户信息保留设置首页，隐私与登录偏好迁入偏好设置，Debug 页面删除；更新、反馈、许可证、主题与 Dynamic Type 保留 | 原生导航与底栏见 `E-20260716-01`；本轮设置 UI smoke 与截图在 CI `35856636143` 通过 |
| AUTH-02、CONTENT-01 | 待验证 | Cookie 父域/Path/Secure/HttpOnly、响应 Cookie 持久化、401/403/登录重定向识别保留；校园服务首次及后续均前台隐藏认证，网络/5xx 不删除凭据且不弹第二登录页 | Cookie 匹配/响应/重试契约保留；隐私 v4、无 Cookie 首次认证和体验账户路径待 macOS/真机回归 |
| SCH-01、SCH-02、HOME-01 | 已完成 | 当前学期按真实日期推导、真实下学期 SDK 接口、重叠课程分栏；首页课程入口、默认可用的拖放编辑、账号隔离布局和已放工具过滤 | Semester、布局、课表 Repository/UI 回归；Rust server feature 编译 |
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
| PAY-04 历史扣款前验收 | Android 生产 WebView | iOS 旧 HEAD 探针已随不可达代码删除；当前只保留生产网页。历史 HEAD 证明不能替代网页交互、银行授权或真实扣款，见 E-20261026-01 |
| 首页编辑可用性 | Android 保留服务端灰度与本地分桶 | iOS 按 2026-10-27 用户决策取消灰度；首页长按、拖放及小工具页编辑入口默认可用，无灰度请求、分桶或启动覆盖。旧偏好仅在迁移清理时移除 |
| 课表 | 主要功能成熟；当前时间指示线有显式 TODO | 先完成行为对齐；时间线作为独立增强项，不阻塞首个课表切片 |
| 课程数据格式 | 旧 `Course` 缓存把 weekday/周次/节次保存为字符串，新教务 Activity 使用整数和 `weekIndexes`；空 weekIndexes 的 Activity 会被丢弃 | iOS `Course` 解码同时接受字符串和整数；存在 `weekIndexes` 时以去重排序后的精确周为准，否则兼容旧起止周范围；畸形数据不触发强制转换崩溃 |
| 课表缓存隔离 | 大部分当前学期缓存带用户前缀，但 `next.schedule` 仍是共享键 | iOS 持久化协议从入口要求 `UserScopedStore`，当前/下一学期均不得绕过用户命名空间；GuiXu 物理键再做 SHA-256，数据库文件不出现学号或业务键明文；旧 UserDefaults/文件缓存只迁移一次 |
| Debug 入口 | App 卡片连续点击 8 次后进入 Debug | 按 2026-09-23 用户决策彻底删除 iOS Debug 页面和八连点入口 |
| 设置点击反馈 | Compose `clickable` 默认提供按压/波纹反馈 | 保持 Android 布局不变，SwiftUI 自定义 `ButtonStyle` 在触摸按下时提供高亮、0.985 缩放和轻触觉；减弱动态效果时只禁用缩放 |
| 电话本 | Android 使用 `ACTION_DIAL`，双校区号码先弹窗选择；号码注释来自 2025 新生手册并含 2026 年 3 月更新 | iOS 保留 9 类 57 个条目及来源说明，统一补 0551 区号；按 2026-10-20 用户要求改为系统 List、Picker、searchable 和 confirmationDialog，号码纵向排列适应大字体；所有号码（含单号码）先确认，再交给系统电话应用，不申请通讯录权限 |
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
| 学生邮箱 | `ui/screen/main/StudentMailScreen.kt`、`data/mail/*`（最新 `b6961a3`） | 本轮接入原生收件箱/文件夹/未读筛选/阅读/写信/回复转发/草稿/联系人/附件与移动，保留隔离的官方网页回退 | E-20261022-02：修复 WebVPN 页面片段，真实复用会话及新 SSO 只读列表均通过；未在测试中向真实收件人发信或移动邮件 |
| 菜鸟身份码入口 | Main 的 `identity_code` 外部淘宝页面 | 没有入口；它不是校园卡付款码 | P3：评估实际用户需求，可作轻量外部跳转 |
| 网费加入首页可选工具 | HomeWidgetRegistry 的 `network_recharge` | 网费充值功能已有，小工具页可用；首页自定义列表尚不包含网费 | P2 小改：补入口映射与旧布局兼容，不能算整项网费功能缺失 |
| 自定义运行期插件 | `ui/plugin/RuntimePluginLoader.kt`、`PluginRegistry.kt`、`.ahup` | 没有动态插件容器 | 暂不直接迁移 Android 动态加载方式；先定义 iOS 扩展范围 |
| 行为预测/个性化与多套 UI 主题 | `personalization/*`、`RadiantComponentPack.kt` | 没有预测系统或 Radiant 界面；已有主题色和首页自定义 | 另行确定产品需求、数据边界；当前优先 iOS 原生体验 |
| 教学评价 | Main 的 `evaluation`、Grade 到教评路由 | 已按用户既定要求整体移除 | 保持既定决策，不自动恢复 |

校园码具体差距已在本轮修复：Android `data/crawler/PaymentQrRequest.kt` 采用学校直连、Rust HTTP 回退、再直连，单通道 12 秒预算；重新打开/强制刷新可以恢复请求，内存缓存 15 秒，后台清空。iOS 增加学校直连并保留 Rust 回退，处理 HTTP 200 的会话失效业务码；取消不启动回退、换账号拒绝旧结果；不缓存或记录真实付款码。学校失败、网络失败仍可能发生，客户端恢复不等于校方服务可用性保证。

问卷 25 人：课程表 22（88%）、校园码 20（80%）、成绩/考试 19（76%）、水电网费及教务通知各 15（60%）、“安大必…”7（28%，全称未取得）、邮箱及其他各 2（8%）。多选结果不能相加当参与人数。“安大必…”不擅自等同学习通。建议先稳定登录/校园码/课表、验证成绩考试，再公告查询与可靠提醒，其后只读账单和电费预警；邮箱排后。公告订阅与用户问卷的教务通知存在关联，但不能宣称范围完全等价。

### 9.2 最新 Android 3.4.7-beta1 源码审计（2026-10-26）

[逐项差距、源码证据与建议顺序](2026-10-26-android-gap-audit.md)。新增确认自定义课程、考勤、详细学籍、通知多来源和食堂众包链路；区分部分已有的邮箱、培养方案、账单、网费与电控。iOS 四个原生标签保持用户确定的结构，不直接迁移 Android 插件、预测和学习通主标签。小工具保留所有已有入口并改为系统列表/搜索/引导，见 E-20261026-01。

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

### E-20261019-10：课表与小工具的原生材质按钮

- 四个顶部动作共用 `NativeHeaderIconButton`：iOS 26+ 通过 `#available` 使用系统 `.buttonStyle(.glass)` 与圆形按钮边框，由系统处理 Liquid Glass、按压和辅助功能表现；移除原课表实色胶囊背景。iOS 17–25 使用 `.regularMaterial` 圆形背景，并提供按下时明暗反馈和轻触觉；兼容样式无缩放动画，遵守减弱动态效果要求。参考 [Apple GlassButtonStyle](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass)。
- 图标与动作保持当前周、课表设置、刷新课表和编辑首页。编辑首页仍受 `home_edit` 灰度控制；UI 演示测试通过已有启动覆盖明确启用，不改变生产灰度范围。按钮保留 VoiceOver 中文名称，验证实际可点击范围至少 44 × 44pt；首次默认玻璃尺寸仅 36pt 的失败已用于修正内容尺寸，未降低断言。
- 空昵称贡献者对应 QQ `257314409`，固定 Android `595e63c` 的 `DeveloperViewModel.kt` 明确为 22级；iOS 保留零宽昵称与 `（22级）` 后缀，不替换为真实姓名。
- 最终验收：iPhone 17 Pro QA / iOS 26.5 的 `build/native-ui/native-header-acceptance.xcresult`，6 项名单/滚动单元测试、2 项 UI 测试全部通过，包含四个动作、真实 44pt 触控范围、编辑首页及单双位周指示器。深色按钮动作另在 `native-header-dark.xcresult` 的 `testHeaderActionsRemainUsableWithNativeMaterials` 通过；该早期结果包的周次可见性断言失败已由最终全绿包复验，不将早期整包记为成功。
- 旧周次测试预设第 5 周一定在首屏，与扩大按钮触控范围后的可见宽度不符，改为逐周选择 2–10 并保留圆形、选中状态与尺寸断言；新编辑入口测试按实际可见“添加小工具”标题判断，不假定 SwiftUI VStack 一定暴露为单一 Other 节点。失败结果包保留在 `build/native-ui/`，未通过降低触控尺寸要求或跳过用例规避问题。
- 视觉证据：`build/native-ui/evidence/schedule-native-header-light.png`、`schedule-native-header-dark.png`、`tools-native-header-light.png` 与 `tools-native-header-dark.png`。默认减弱动态效果关闭，深色检查结束后恢复 QA 模拟器为浅色。本机仅有 iOS 26.5 运行时；iOS 17–25 分支已通过最低部署版本 17.0 的编译检查，未声称完成旧系统运行验证。

### E-20261019-11：共享玻璃按钮组与紧凑课程详情

- 课表的当前周、设置、刷新改为原生 `ControlGroup(.navigation)`，三个独立 44pt 原生按钮共享一个胶囊背景；iOS 26+ 使用系统 `glassEffect`，iOS 17–25 使用 `regularMaterial`。小工具单个编辑入口维持上一轮原生圆形按钮，不改变灰度范围。参考 [Apple ControlGroup](https://developer.apple.com/documentation/swiftui/controlgroup) 与 [Liquid Glass 自定义视图](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)。
- 旧课程详情的竖向 `Divider` 把地点/教师行撑高，固定 300pt detent 又挤压上方周次。本轮移除竖线与 72pt 最小行高，地点和教师按文本自然高度顶对齐；详情高度取内容实际测量值，仍保留系统 sheet、拖动指示和展开能力。上课日/节次与周次分行，所有文本完整换行；无障碍字号自动使用大 sheet，地点/教师改纵向排列，内容可滚动。
- 新增 UI 验收覆盖普通课程的紧凑高度与 metadata 行高、40 个不连续周次的完整内容及超两行实际布局、长地点/多教师、无障碍最大字号的滚动访问；沿用已有 demo endpoint 注入，不新增生产调试入口。顶部三个动作及小工具编辑、单双位圆形周指示器继续回归。
- 本机 Xcode 27 / iOS 26.5：`build/native-ui/grouped-course-details.xcresult` 中三个详情 UI 用例与圆形周次回归共 4 项通过；三个顶部按钮的独立 44pt 触控断言通过。该包的按钮测试将“共用背景”误写为“按钮间距为零”，实际原生 ControlGroup 间距为 8pt，已修正该断言；后续重跑在测试准备阶段被终止，不记录为通过，原失败包均保留。
- 用户明确仅使用指定的 iPhone 17 Pro 后，后续仅在 `64F2DE05-3F35-4563-85C7-00378E4F42B8` 保留数据覆盖更新并可视化验证，未卸载/重置/切换体验账户：真实第 8 周回到当前第 7 周、打开/关闭课表设置、真实课表刷新后课程恢复、真实课程详情的全部地点和教师文字均确认成功。保存深浅色 `schedule-grouped-real-light/dark.png` 和 `course-detail-real-light/dark.png`；预览后恢复浅色，ReduceMotion 保持关闭。此前独立 QA 也是 iPhone 17 Pro 型号，但此后不再使用。
- 长文本压力图 `course-detail-full-weeks.png` 显示 40 个不连续周次完整占四行，地点和多位教师完整换行；最大无障碍字号使用滚动区域。上述图片位于 `build/native-ui/evidence/`，不提交真实账户资料/截图。最低部署系统仍是 iOS 17；iOS 17–25 分支仅有编译验证，本机没有其运行时及 iOS 27 运行时。

### E-20261019-12：合并前 CI 稳定性与 1.0.2 打包

- 合并前回读上一轮 CI `39271523323`：单元与业务 UI 组通过，设置组在后续提交触发取消前出现两处失败。校园码用例在展开动画期间分别查询宽高，读到了瞬时 0pt 宽；现在等待实际方形布局就绪，并从同一 frame 快照验证尺寸，不放宽 138pt 下限。开发者用例先判断滚动头像可点击、再重新获取点击点，期间头像已移出有效区域；现在从裁剪行内的完整可见头像取得坐标执行真实单/双击，继续断言贡献浮窗、暂停/恢复及 QQ 降级提示。
- 修正仅涉及 UI 测试同步方式，不关闭生产动画、不跳过用例、不修改真实业务。后续本机仅使用用户指定的已登录 iPhone 17 Pro，不重置或以自动测试覆盖其真实登录；CI 使用独立 iPhone 17 Pro。
- 修正后在用户指定 iPhone 17 Pro / iOS 26.5 上通过 `build/native-ui/retained-session-final.xcresult`：校园码展开/尺寸/收起、贡献浮窗/暂停/恢复/双击 QQ 共 2 项通过，0 失败。UI runner 通过测试专用 `AHUTONG_UI_RETAIN_SESSION` 保留真实登录，不传重置或 demo 参数，不改变生产代码；测试宿主编译亦通过。
- 合并前 Release iphoneos / arm64 构建通过，App 与 Widget 均为 1.0.2 (3)、最低 iOS 17；双方 App Intents 元数据、共享组、隐私清单及扩展结构校验通过，4 项 Python 校验测试通过。最终合并提交与 IPA 校验记录随交付保存到忽略的构建目录。

### E-20261020-01：Windows 重签后的 Widget 共享修复

- 用户确认使用 Windows Sideloadly 直接安装，并拥有 Developer Program Apple ID；没有重签后 IPA。不再要求导出签名包作为继续开发的前提。目标仅为 Widget，未修改 Siri、未合并 #2，也未更新 AIO gitlink。
- 对既有 `8b2916c` IPA 执行 codesign 检查，主 App 与 Widget 均无签名，也无可供重签工具读取的 App Group entitlement；旧结构检查未覆盖此项。新增 `package-resignable-ipa.py`，先为扩展、再为 App 添加仅声明共享组的 ad-hoc 签名，并验证压缩前后声明。没有开发者证书、Team ID 或描述文件，仍须实际开发者重签；CI 使用同一脚本和 `--require-entitlements` 门禁。
- 共享容器优先使用配置组；仅当重签后双方描述文件属于同一团队且存在唯一共同组时尝试适配。候选最终必须通过系统 `containerURL`，不能把描述文件声明当作实际授权，不会回退到 App 私有目录。原组已获授权时不改用其他组；多组歧义、团队不同、扩展丢失、双方配置不同均明确失败。
- 读取 embedded.mobileprovision 仅作为可缺失的侧载兼容线索；格式/大小不符时失败关闭，正常配置组路径不依赖该格式。遵循 [Apple TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles) 的非稳定格式边界；未使用私有 entitlement API，也不尝试自行授予权限。
- 小工具的现有添加指引显示具体共享失败原因，并提供系统 ShareLink 导出版本、App/Widget 标识、组与检查结果；不导出账号、Cookie、课程、设备标识、证书、完整描述文件或容器路径。Windows 无需导出签名 IPA，即可从安装内分享摘要。Developer 会员身份与本次签名已配置 App Groups 分开说明，步骤见 `docs/release/readiness.md`。
- 仅在指定 iPhone 17 Pro `64F2DE05-3F35-4563-85C7-00378E4F42B8` / iOS 26.5 测试，未使用其他设备，未卸载、清空或执行重置。首次保留会话 UI 启动发现已为登录页，该失败保留在 `build/widget-sharing/guide.xcresult`；随后只用不写入 Keychain 的内存 demo session 检查指引与系统分享，不记录为真实账号成功。
- 最终 `build/widget-sharing/unit-final.xcresult`：14 项组配置测试 + 6 项快照测试全部通过，包含主 App 与 Widget 分别从包中发现改名组并实际读写同一快照、拒绝多组/异团队/未授权与坏描述文件，以及摘要排除隐私字段。Python 16 项通过，包含原组/改名组的签名与描述文件约束、权限声明缺失和 AppleDouble 文件回归。
- `build/widget-sharing/guide-memory-session.xcresult`：1 项原生指引 UI 通过，实际点击系统分享并关闭、返回指引再完成；截图在 `guide-memory-attachments/`。设备 Release 构建通过，App/Widget 统一 1.0.2（4）。首个打包试验因 ditto 将 AppleDouble `._*.app` 混入 Payload 触发检查失败；最终禁用资源叉/扩展属性并只识别真实 bundle 目录，同时新增回归和压缩后验证，不交付首个试验包。
- 最终候选 `build/widget-sharing/AHUTong-1.0.2-4-widget-sharing-resignable.ipa` 通过包结构、双方 App Group 声明及签名完整性检查；原 `8b2916c` IPA 被新增门禁拒绝，证明补齐此前遗漏。最终 Sideloadly 签名能力、iOS 27 组件同步/配置仍需用户覆盖安装复验，不将 Simulator 或 ad-hoc 声明当作有效团队签名已通过。

### E-20261020-02：岛卡圆角与十分钟边界、原生电话本

- 基线为官方 iOS main `8b2916c`，分支 `fix/island-phonebook-ui`；AIO 使用独立 detached worktree `.worktree/ios-island-phonebook-fixes`，只初始化 iOS 与构建需要的两个依赖，未修改 AIO gitlink。
- 岛卡规划与系统 Activity 创建入口共用 `0 < 距上课秒数 <= 600` 校验，超过十分钟或已上课的计划均清理；当天/周次/校区时区与课中抑制语义保留。原生计时区间同步缩为十分钟，采用分秒格式，继续由系统逐秒显示。
- 展开岛卡将短状态放在摄像头两侧，课程标题与地点/倒计时放入底部区域，并加入水平/底部安全留白；压缩态倒计时收窄到分秒所需宽度。截图中课程名、地点与数字完整位于圆角内部。
- 电话本改用原生 List、分类 Picker、searchable 与逐行 confirmationDialog。保留 9 类 57 个本地条目、部门/分类/号码全文搜索、0551 区号、单号与双校区拨号确认；长名称与号码纵向换行。确认弹层附着在触发的行，iOS 26 的原生浮窗由系统提供点外部关闭，未自绘尺寸或分隔线。
- 本机 Xcode 27 / iOS 26.5 / 独立 iPhone 17 Pro QA：App、Widget、测试目标 `build-for-testing` 成功；`build/IslandPhoneBookUnits.xcresult` 19 项定向单测通过，覆盖 10 分钟整、提前 601 秒、2:47:18、上课/课中、时区、并发禁用、目录与号码契约。
- 首轮 `build/IslandPhoneBookUI.xcresult` 中原生边缘/内容返回手势、远期计划不创建、后台在上课前消失共 3 项通过；另外 3 项失败的证据保留：倒计时组合辅助功能节点报告整个 region 的宽度，已改测 Vision 识别的真实数字像素；iOS 26 原生浮窗不显示取消行，已改走系统 `PopoverDismissRegion` 的外部点击关闭。未放宽倒计时递减和圆角内部留白要求。
- `build/IslandPhoneBookUI2.xcresult` 中岛卡真实像素边距/原生倒计时递减及最大无障碍字号的原生分类/单号确认两项通过；搜索空态最初误断言固定“无结果”标题，实际系统标题包含搜索词，已按实际系统状态与零条目断言，`build/PhoneBookSearchValidation.xcresult` 回归通过。浅色截图见 `build/IslandPhoneBookUIAttachments2/`，包括 `DE87B980-8DB3-4338-A540-32AB3FC1D212.png` 岛卡和 `71FC2C0C-4A86-4596-8917-9274647D51B3.png` 双校区菜单。
- 通过 `simctl ui appearance dark` 设置独立 QA 设备的真实系统深色模式后，`build/PhoneBookDarkValidation.xcresult` 两项电话本 UI 全部通过，包含分类、最大无障碍字号、双校区确认、外部关闭与空搜索；已逐张目视检查 `build/PhoneBookDarkAttachments/` 的列表/菜单/大字体截图，测试后恢复浅色。六个独立 UI 场景均已有通过证据（其中电话本两场景另在深色模式复验），不将保留的首轮失败结果标记为整套通过。
- 合并前同步上游 `0153ef1`，保留 E-20261020-01 的 Widget 共享组、重签检查与 1.0.2（4）。PR #8 首轮 CI 的 509 项单测、5 项导航 UI、7 项服务 UI 通过；设置组 28 项中两项岛卡测试失败，电话本两项通过。证据保留在 run `39389808697`，未标为整套通过。
- CI 录屏中首次长按后仍为折叠态，测试现确认标题出现后才检查布局，必要时按逻辑屏幕坐标重试。后台截止检查改用新截图的倒计时像素，排除左侧系统时钟，仍会拒绝可见的 `0:00`；本机复现旧 AX 子树一直存在但画面已清空，`build/PR8IslandDeadlineRegression.xcresult` 两项回归全部通过，保留展开边距、原生计时递减和后台截止截图。未修改产品行为或跳过测试。
- 第二轮 CI `39396640851` 的 509 项 Swift 单测、25 项 Rust 测试、16 项打包检查及导航/服务组通过；设置组 27/28 通过，含岛卡展开/递减、后台截止、前台截止和电话本两项。剩余失败发生于首次 App 启动约 73 秒后，录屏在失败结束时仍停留启动画面，fixture 的 5 秒谓词等待未得到完成状态；现直接查询标识和“未创建”完成状态并给出 30 秒上限，未修改边界断言。`build/PR8DistantCourseRegression.xcresult` 本机定向回归通过。保留两轮失败记录，不将分散通过的结果记作一次完整 CI 全绿。
- 本轮没有新增 APNs，也没有改变主线的后台预算策略。岛卡仍在打开 App/刷新课表时维护；没有承诺 App 不运行时自动于课前十分钟创建，后台预算耗尽时可提前结束。未执行真实拨号；物理 iPhone、iOS 17–25 与 iOS 27 运行时仍需后续回归。

### E-20261020-03：1.0.3 版本与仓库维护

- 使用独立 AIO detached worktree `.worktree/ios-1.0.3-maintenance`，仅初始化 iOS 与两项编译依赖；快进纳入 E-20261020-02 的全部修复，统一通过 PR #8 校验。App 与 Widget 的 Debug/Release 四份生成配置均为 1.0.3（5），XcodeGen 生成及配置读取断言通过。
- README 移除占位 Bundle ID、旧 Windows 环境和模拟器占位参数，明确 iOS 17+、开发环境、GitHub Actions 下载、7 天产物保留、重签安装和扩展保留步骤。相对链接存在、过期文案检查及 `git diff --check` 通过。
- GitHub `Protect main` ruleset `25464481` 为 active，范围仅 `refs/heads/main`；禁止删除、禁止非快进更新、要求 PR，审批人数为 0，无绕过主体。通过分支有效规则接口回读三项规则，未新增 CI 必须项或额外审批门槛。
- `docs/ci.md` 按 run `39389808697` 的步骤时间和 XCTest 日志记录四组耗时；最长设置组约 30 分钟，其中串行 UI 17 分 53 秒、模拟器 2 分 45 秒、编译/准备 7 分 7 秒。记录后续分片与复用构建方向，本轮未缩减测试覆盖。
- 本轮构建沿用 `Build unsigned IPA`，主 App 与 Widget 统一校验并保留 App Group 声明；产物需用户重签安装，不写入 Apple 账号、证书或描述文件，不更新 AIO gitlink。

### E-20261020-04：CI 构建复用与均衡分组

- 将四次重复编译改为一次 `build-for-testing`；五组任务通过 `test-without-building` 复用同一运行的 tar 产物，保留执行权限及符号链接，执行前核对 Xcode 与 Simulator SDK。导航组先运行全量单测，避免再占一台 Mac runner。
- 40 条 UI 用例按逐项耗时均衡分配，校验脚本拒绝漏分、重复和失效选择；保留五台独立模拟器、组内串行、真实倒计时等待、支付禁写、域名阻断、截图与 xcresult。
- 修正自动化同步：Tab 切换和电控选中值使用有界等待，大字体电话本 Popover 从原生导航栏外点关闭，支付保留服务端成功断言并等待有效快照，快捷指令使用原生属性等待可点击。UI 失败用例最多在新测试进程复验一次，两次结果保留；复验通过显式 warning，连续失败仍使 CI 失败。单测不自动复验。
- 最终云端 [39428134231](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39428134231) 全绿：509 Swift 单测、40 UI、25 Rust、22 Python；40 条 UI 均首次通过，没有触发复验。与优化前最后一次成功运行相比，含排队总用时 29 分 22 秒 → 23 分 58 秒，缩短 18.4%；累计 job 用时 84 分 16 秒 → 81 分 54 秒。分组时间、计算口径和失败诊断记录见 [CI 文档](../ci.md)。
- 本机跨目录恢复 tar 后 509 单测通过；通用 Simulator `build-for-testing`、22 Python 检查、40 UI 分组审计通过；页面巡检、两条电话本、完整支付及两条快捷指令用例复验通过。macOS Bash 3.2 下五组 UI 步骤、失败退出码和复验告警均检查通过。
- README 统一链接安装文档，补齐 Mac + Developer Program 的同 Team、共同 App Group、源码安装与现成 IPA 重签步骤；未修改应用功能或 1.0.3（5）版本，未更新 AIO gitlink。

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
- [x] 历史 PAY-04 HEAD 验收曾完成；2026-10-26 已删除无可达入口的实现与专用测试，生产 WebView 安全边界保留。
- [x] 通用学校官方探测和隐藏 Debug 均已删除；不恢复历史验收入口。
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

### E-20261022-01：续期唤起、Widget 恢复、原生邮箱及显示维护

- 基线：iOS `main 6b843b7`；Android 官方 `master b6961a3` 只读对照，未修改 Android 源码及 AIO 主工作区 gitlink。
- 校园码：隐藏认证前短暂等待前台/Key Window 就绪，超时保持可恢复错误；恢复活动状态允许一次 QR 重试，分钟/15 秒定时器仍不反复重试失败。保留取消、请求版本检查和真实会话凭据，不将暂时网络/活动状态错误解释为密码失效。
- Widget：共享组仍受系统授权约束；不永久缓存一次失败的容器解析。课表快照显式使用首次解锁后可读的文件保护；安装摘要始终可分享，不含个人信息。不能用本轮模拟器通过宣称 Windows Sideloadly 已取得实际 App Group 权限。
- 主题与课表：极光蓝为默认，`default`、历史 `blue` 和已保存极光蓝 Hex 归一选择；旧默认紫保留为“鸢尾紫”。总览非本周课程用灰色，每张卡使用与当周一致的连续 8pt 圆角，不再把叠放组当作单个裁切区域。
- 导航：小工具/设置使用各自根导航标识；点击和离开均清理旧子页面，覆盖程序切换及外部 URL 后重新进入。保留系统 TabView。
- 邮箱：原生列表、文件夹、未读、筛选已加载邮件、阅读、回复/转发、写信、草稿、联系人、附件和移动；富文本/内嵌云附件可进入临时官方 WebView。邮箱 SID / Cookie 独立存 ThisDeviceOnly Keychain；每次请求检查当前校园账号，退出清除。HTTP 只跟随白名单 HTTPS 路由，学校与邮箱及 VPN Cookie 分区；只读过期至多续期一次，发送/草稿/移动无自动重放，发送结果丢失时锁定再次发送。
- 隐私 v5 补齐邮箱服务主机、会话和内容用途；不增加跟踪。旧版本会要求重新确认政策，保存的登录会话不因政策版本号清空。Debug UI 的演示/协议/重置参数统一使用独立的协议与体验偏好 suite、内存 SecureStore 和禁用的真实缓存清理，不替真实用户接受政策或清除凭据。
- 验证设备仅 iPhone 17 Pro（`64F2DE05-3F35-4563-85C7-00378E4F42B8` / iOS 26.5），无卸载/清空或其他模拟器操作。Xcode 默认 Simulator 签名后，525 Swift 单元/契约测试已通过；邮箱与总览/主题/外部导航 5 项 UI、隔离后的体验/隐私 2 项 UI 通过，结果为 `build/source-audit-20261021/maintenance-final-6.xcresult`。校园码优先级和 Widget/设置根页共 4 项 UI 在 `maintenance-card-widget-navigation-7.xcresult` 通过。截图导出至同目录 `preview-final/`，已目视检查原生邮箱阅读/写信与总览叠放卡片。初轮关闭签名仅 Keychain Adapter 返回 -34018，正常签名复验通过；未跳过该测试。脚本测试 22 项及全部 45 个 UI 测试的分组校验通过；并未声称本轮执行了全部 45 项 UI。
- 旧测试风险：早期回归执行的 `testExperienceAccountCannotOpenPaymentCode` 使用了真实默认 session/consent 存储，可能影响既有模拟器登录，已向用户说明。随后对 RootView 的 UI 测试存储实施隔离，并复验体验账户和拒绝隐私流程；这不应被记为“原有登录已验证保留”。旧测试自动写入的新隐私确认已单独撤销，待用户本人重新确认；未读取或导出真实凭据。
- 冷启动与重复校园码跳转、快捷指令引导另 3 项在 `maintenance-shortcuts-8.xcresult` 通过，本轮最终源码累计验证 14 项不同 UI 测试。
- 新测试：前台就绪/超时/取消，QR 失败后的恢复入口，Widget 暂时无容器后的恢复，邮箱生产 JSON 与转义/路由/账号隔离/一次续期/未知发送结果及官方回退边界。旧主题测试“默认紫/极光蓝次序”已按新需求修改；新 UI 的天气标题、主题按钮定位及总览旧数据注入参数已纠正，保留失败记录。
- 边界：不进行真实充值、真实发信或真实邮件移动；不将合成契约与 UI 通过写成真实邮箱全部验收，也不宣称 iOS 27 Siri 裸短语或 Sideloadly 授权已通过。

### E-20261022-02：真实邮箱登录、浅灰总览与周日周视图

- 维护基线为本地 `6151d46`，继续使用当前 session 的 iOS 分支；未修改 Android、AIO gitlink 或版本号。
- 真实邮箱故障定位：学校门户在邮箱 SSO 请求后返回带 `#` 片段的 WebVPN 地址，原 iOS 额外的 fragment 禁止条件误报“不受信任的地址”。对照 Android `StudentMailSession.secureUrl`，在可信域名/凭据检查之后移除只用于页面导航的 fragment，再执行 HTTPS/端口检查。保留域名白名单、账号边界与 Cookie 分区，不记录 URL、票据或邮件正文。
- 真实只读验收仅在 iPhone 17 Pro（iOS 26.5）进行：正常 App 复用已有邮箱会话成功；随后通过一次性 Debug 诊断及独立内存 SecureStore，完整走门户 → WebVPN → 网易入口 → 学校邮箱的新会话路径，也成功取得 8 个文件夹和首批 30 封列表。日志仅包含步骤/服务类别/HTTP 状态/数量，位于 `build/source-audit-20261021/mail-read-only-probe-1.log` 和 `mail-fresh-session-probe-1.log`。不发信、不标记已读、不移动邮件、不改变原邮箱会话；一次性诊断代码已移除。真实写入和附件仍为验收边界。
- 课表：非本周改用更浅的中性灰底及适应深浅色的灰色文字，保留每张卡 8pt 连续圆角；“每周开始于周日”默认关闭，仅改变展示，周日到周六日期连续。每个课程仍映射到原有实际日期；“回到当前周”和当天高亮跟随展示周。学期最后一个周日通过“末”页保留，不引入第 21 教学周；未知下学期日期仍显示占位。
- 测试隔离：`.defaultAppStorage` 让演示 UI 的开关写入测试 suite；宿主 XCTest 环境同样隔离 RootView 的会话/协议，防止真实启动续期加入模拟请求的全局协调任务。初轮全量测试发生 4 个断言/异常失败，修复后 531 项（其中 1 个手动项跳过）全部无失败。曾尝试从单元测试宿主进行真实验收，但其凭据上下文无法读取正常安装的会话；该临时测试已删除，真实验收改由正常 App 完成；正常启动后已核实原登录仍可用。
- 新增模型/契约测试覆盖：WebVPN/邮箱 fragment 归一及恶意域名/明文 VPN 拒绝；默认周一、跨年连续日期、20 周所有课程日期往返映射、周六到周日及最后周日。新 UI 验证周日开关、对应日期和课程列、重启持久化及关闭恢复。最终结果 `build/source-audit-20261021/mail-week-start-final-3.xcresult`：530 单元/契约、10 UI 全部通过，无跳过；Python 22 项和全部 46 项 UI 分组校验通过。合成 UI 截图见 `week-start-preview/`，已目视检查浅灰卡片、独立圆角、设置原生材质与周日连续日期。

### E-20261022-03：1.0.4 合并前全量 CI 发现与修复

- Actions `39792897121` 对 1.0.4（6）执行完整回归；530 项单元/契约、支付 5 项、设置 13 项、导航 5 项 UI 均通过。实况活动组的 5 项岛卡与 4 项快捷指令测试通过，顶部按钮测试在两次执行中均失败于“添加小工具”未出现。
- 根因是本轮引入的测试存储隔离：`HomeView` 的 `@AppStorage("home.request-edit")` 已使用测试 suite，但工具页回首页的入口仍写 `UserDefaults.standard`。统一通过 `AppRuntime.sessionDefaults` 写入，避免测试模式跨存储，也不通过放宽 UI 断言掩盖问题；原始失败日志/截图保留在 `build/source-audit-20261021/ci-1.0.4-live-activity/`。
- 修复后，仅使用已授权的 iPhone 17 Pro（iOS 26.5）运行原有完整 `testHeaderActionsRemainUsableWithNativeMaterials`，课表三个共享材质按钮、回到当前周、刷新、设置与工具页编辑首页全部通过，原断言未修改。证据为 `build/source-audit-20261021/version-1.0.4-header-edit-fix.xcresult`；真实账号数据与 Keychain 保留。
- 校园服务组的详细日志另显示：新增工具/设置导航回归未传天气 fixture，导致 CI 依赖真实天气外网并在等待天气卡片时失败；整组重试随后触及 job 时限。该测试补齐已有天气注入入口的合成数据，按天气卡片标识查找实际 AX 元素类型，并明确核验天气设置按钮可点；保留天气子页、退后台、外部深链、工具/设置返回根页及重复选择断言，不扩大 CI 超时或减少测试范围。日志为 `build/deliverables/1.0.4-candidate-139/ci-services.log`。
- 天气 fixture 修复后的完整导航回归在同一 iPhone 17 Pro 通过，证据为 `build/source-audit-20261021/version-1.0.4-navigation-fixture-fix.xcresult`；测试后恢复正常账号课表页面。
- 同一提交被 push 和 pull_request 重复触发全量 CI；确认提交与合并预览代码树完全相同后取消排队的重复运行 `39792959419`，保留完整分支回归。未修改 workflow 的测试范围或合并规则。

### E-20261023-01：小组件数据、固定课表表头、返回菜单及校园码恢复

- 基线：远端 main `9e8478a` 与本地一致，检查时无开放 PR；PR #10 已合并，1.0.4（6）IPA 的 main Actions `39802035511` 成功。新建 `codex/ios-widget-navigation-reliability`，不修改 Android、版本或 AIO gitlink。
- 用户补充：Widget 可以添加，但课程为空或显示异常。模拟器正常账号的共享快照为 ready、第 7 周、11 条当周课程/18 条全部课程；这只证明本机数据已写入，不能作为 Windows Sideloadly 签名和 iOS 27 桌面渲染的验收。
- Widget 数据缺陷：`Course` 在 `weekIndexes` 为空时使用起止周范围，原快照直接复制空数组，随后被组件周次过滤清空。改用 `activeWeeks`，并新增当周、下一周及超出范围三种结果测试。已有有效缓存和周次时，首页/课表先发布缓存快照，再等待网络校准，避免退出或网络缓慢时一直没有数据；未知周次仍不发布虚构第 1 周。
- 隔离与指引：演示/宿主 XCTest 的 Widget 读写改为测试私有快照，避免示例课表覆盖真实 App Group；提醒偏好沿用隔离 suite。安装指引显示同步状态和课程数量、提供“打开课表同步”，分享摘要只新增状态/周次/数量，不包含课程名称、地点、账号、Cookie 或设备标识。未同步和网络同步失败不再误称“登录失效”。
- 课表与导航：对照当前 Android `Schedule.kt` 中固定的 `ScheduleHeaderRow`，顶部周选择及三个系统材质动作留在滚动区外，网格继续纵向滚动/横向分页；周日视图和固定课程日期不变。工具首页补 `.navigationTitle("小工具")`，保留系统返回历史菜单。
- 校园码：前台/快捷指令/展开面板初次加载合并在途请求，快捷指令不再强制取消首页预取；后台仍清除旧码。会话最多续期一次，续期后直接通道仍失败时允许 Rust 通道读取，取消不触发回退；显式点击刷新继续可替换挂起请求，不引入计时器无限重试。
- 验证：仅使用 iPhone 17 Pro / iOS 26.5 / Xcode 27.0，最终 537 项单元/契约无失败；受影响的 15 条 UI 路径均通过。`final-regression.xcresult` 中 14 条 UI 直接通过，旧分页用例因未隔离上次保留的下学期预览设置而失败；改为通过设置 UI 明确恢复初态，避免启动参数覆盖后续开关切换，保留原有左右分页、总览及下学期断言。最终 `verified-regression.xcresult` 的全部 537 项单元/契约与分页、返回标题、冷启动二维码 3 条 UI 均通过。日志/原失败证据均在 `build/source-audit-20261023/`，未降低断言或扩大等待。
- UI 与视觉证据：上下滚动前后周选择/操作按钮坐标固定；周日连续日期、重入所选周、顶部原生按钮、重复快捷指令、后台返回及工具/设置根页回归通过；原生返回按钮明确断言“小工具”，长按中间状态截图 `native-back-held.png` 实际显示“小工具”菜单项。三尺寸 × 深浅色 Widget 合成渲染图与同步指引截图已导出目视检查。
- 正常账号只读验收：测试后无演示参数启动原 App，数据和 Keychain 保留；真正进程冷启动深链、退后台返回、从课表重复深链均显示真实二维码，本次未见加载失败/重试或重新登录提示。用本机 Vision 只输出二维码存在与错误文案存在的布尔值，不输出付款码内容或 OCR 文本；无充值/支付。桌面已添加的小尺寸 Widget 实际显示第 7 周的真实接下来课程，截图 `real-widget-home.png`；共享快照仍为 ready、11 条当周/18 条全部记录。证据在 `build/source-audit-20261023/`，真实二维码截图仅本机保留，不发布；iOS 27 / Sideloadly 实际签名授权及显示仍须另行实机复验。

### E-20261023-02：Sentry 接入与用户安装签名诊断

- 基于已合并 PR #11 的 develop `f7a79e0`。使用当前会话工作区的新功能分支 `codex/ios-sentry-widget-diagnostics`，版本保持 1.0.4（6），不改 Android 或 AIO gitlink。
- 用户提供的 v1 摘要：扩展存在、配置组一致，但主 App 描述文件 groups 为 none、Widget 描述文件不可读，配置组容器也无法访问。这是当前安装缺少共享权限的证据；原 `Same profile team: false` 因两份信息不齐不能推断团队不同。v2 改为 unknown，并新增 appGroupNotProvisioned 精确提示。没有引入私有目录伪共享，也未声称给 Sideloadly 安装授予权限。
- 按用户指定 AHUTong-iOS 建立 Sentry 项目；服务将 slug 规范为 ahutong-ios，组织为 ratatoskr，使用 DE 接收节点。固定官方 Apple 二进制包 9.31.0，补齐 MIT 离线许可。仅当前 v6 隐私确认后启动；拒绝、撤回和测试隔离不启动业务上报。
- 过滤 SDK 事件的用户、请求、任意附加字段、异常原因、栈变量与内存寄存器；业务诊断只接受封闭枚举和数字错误码，按进程去重并限量。覆盖共享权限/写入、续期和校园码最终失败，不传课程、邮件、凭据或二维码。关闭自动网络采集、日志、回放、截图、视图层级、性能和指标；服务端保存默认清洗、额外敏感字段以及禁止新事件存储 IP。
- 只使用 iPhone 17 Pro / iOS 26.5 / Xcode 27.0：全部 545 项单元测试中 544 通过，1 项真实投递测试按默认隔离策略跳过；随后显式传入 AHUTONG_SENTRY_SMOKE=1，仅该合成测试通过并由浏览器确认收到事件 3161569339c145ed86d6a19fe133f81a，项目 AHUTONG-IOS-1、用户数 0。另 4 条 UI 覆盖隐私拒绝、Widget 指引、冷启动与重复快捷指令，均通过。证据在 build/sentry-20261023/，无真实校园请求或充值。
- Release 真机目标与保留 Widget 的待重签 IPA 结构验证通过，App/Widget dSYM 均生成。Actions 补保留匹配 dSYM 和可选上传步骤；脚本只扫描 .dSYM，不上传源码，令牌只从环境读取。CI/产物脚本测试 25 项通过。上传令牌创建及写入 GitHub Secret 尚待用户确认；收件成功不等于已完成 Debug 符号化，用户 iOS 27 签名与组件显示仍需实机复验。

### E-20261024-01：CI 符号上传与隐私审计收口

- 用户明确允许创建 `AHUTong-iOS GitHub Actions` 组织令牌（固定 org:ci）并保存到 OpenAHU/AHUTong-iOS 的 `SENTRY_AUTH_TOKEN`。Sentry 页面确认令牌名称，GitHub 页面与 API 均确认 Secret 已保存；凭据不进入源码、IPA 或命令参数。
- 在源码 `0644586` 重跑 IPA #144 与 Archive，双方均上传两份匹配 dSYM，Sentry CLI 等待服务端处理后分别返回两个 OK。项目 Debug Files 页面确认四份文件含 symtab/debug/unwind；具体 Debug ID 和运行链接见 `docs/operations/sentry.md`。不宣称历史 Debug 合成事件已补齐符号。
- 发现并修正过时的“不接入第三方崩溃上报”文档和恒定关闭的诊断测试。删除 ReleaseDiagnostics 未被业务使用的隐私、支付开关及崩溃标志，将实际随包隐私清单检查放到测试中，核对诊断类型、不关联身份、不用于跟踪和 App 功能用途。README、隐私映射和设备验收说明统一为 v6。
- CI 日志确认新进程重试会重复整组所选 UI。原 25 分钟不足以覆盖两轮和保存结果，UI job 预算改为 40 分钟；仍最多重试一次，保留失败证据与 warning，持续失败照常失败。不减少 48 条 UI、断言或真实等待，更新 docs/ci.md 的历史/当前测试范围和重试语义。
- 仅使用 iPhone 17 Pro / iOS 26.5 / Xcode 27.0，清理后的全部 545 项单元测试中 544 通过、1 项显式投递默认跳过，设备 Release 构建通过。原 CI 首轮出现等待失败的校园码展开、体验账户进入课表两项本机均一次通过；日志为 `build/sentry-20261023/ci-wait-regression.log` 与 `privacy-audit-regression.log`。保留原失败和重试证据，不将超时结果写成通过。
- 源码 `0644586` 的完整 CI run 39972435515 attempt 2 最终成功：五组共 48 条 UI 全部通过，设置/服务两组重跑各 14 项均在该次执行首次通过，没有隐藏的新失败；导航组的 545 单元为 544 通过、1 跳过。后续仅删除上述未使用审计数据、更新实际清单测试与 CI 预算；最终本机单元/设备构建证据使用清理后的源码。

### E-20261025-01：IPA #145 内嵌资源框架签名修正（仅本地）

- 用户截图为系统安装阶段“无法安装此 App，因为无法验证其完整性”，不是 App 启动或 Widget 空白。用户明确要求暂不触发新 Actions；本次没有推送、手动触发或重跑工作流，版本保持 1.0.4（6），AIO gitlink 不变。
- 直接下载并审计成功工作流 `40071473337` 的原始 `AHUTong-unsigned-ipa-145`：SHA-256 与附件一致，ZIP 完整，App/Widget 结构、权限声明和各自签名均通过；主 App 的 `codesign --verify --deep --strict` 也通过，但单独严格检查 `Frameworks/Sentry.framework` 失败，资源未被完整签署。旧检查器未检查这一层，会错误放行该包。该缺陷与系统错误相符，尚不能仅凭通用弹窗确定它是 Windows 重签后失败的唯一原因。
- `Sentry-Static` 代码已静态链接到 App，主程序无 Sentry 动态依赖。设备 Release 构建日志确认 Xcode 在复制静态框架资源时生成 iOS `100.0` 占位二进制并带链接器临时签名；本次保留该结构及隐私资源，修复的是遗漏的完整资源签名，不改最低系统版本或移除 SDK。
- 打包脚本按嵌套深度先签所有 `.framework` / `.dylib`，再签 Widget/App；只有 Widget/App 声明共享组，不添加团队或描述文件。检查器在两种签名检查模式中均逐个严格验证内嵌代码，明确输出失败框架的相对路径，不依赖 `--deep`。
- Xcode 27.0 / macOS 上的 28 项脚本测试全部通过。新增三项使用真实 arm64 iPhoneOS Mach-O 与 codesign，覆盖“外层有效、内层未封装资源”拒绝、打包后框架与 Widget 内动态库签名/隐私资源/共享声明保留，以及外层重新签署仍不能掩盖内层资源篡改。没有启动其他模拟器或操作真实账号。
- 原始 #145 现被新检查器明确拒绝；由同一份原始 IPA 在本地重新打包的候选通过 App/Widget/框架逐个严格验证、共享声明、Intents、ZIP 与可执行权限检查。三份隐私清单逐字一致，三份 Mach-O UUID 未改变，原有构建对应的 dSYM 仍匹配。没有重新编译业务代码、创建新 Actions 构建编号或上传新符号。
- 本地候选位于 `build/deliverables/1.0.4-145-local-signing-fix/AHUTong-1.0.4-6-145-local-signing-fix.ipa`，SHA-256 为 `37fa5a8a17dc467ddbc1396d3a57ed20d7ec5d42580a9e49b2ff4a106ea6d2a3`；检查结果为同目录 `verification.json`，原始产物及旧检查结果保留在 `build/ipa-145-install-audit/`。候选仍需用户开发者账号重签；Windows Sideloadly / iOS 27 安装、最终团队授权与 Widget 显示仍待实机复验，不将本地 ad-hoc 验证写成真机通过。

### E-20261025-02：本地体积、性能与最小诊断候选

- 范围：同一 worktree 和 PR #12 分支，AIO gitlink 不变。用户要求先优化大小/运行速度、打包并用本机向测试 iPhone 安装验收，继续遵守暂不触发 Actions 的约束；本轮没有推送或触发 CI。App/Widget 统一为 1.0.4 (7)。
- 审计实际 #143/#145 IPA 与对应历史 Archive：#145 IPA 为 9,536,231 bytes，解压 35,471,706 bytes；App/Widget 含 LLVM 覆盖率，App 符号表和字符串约 19.97 MB。原 scheme 测试覆盖率泄漏到普通 Release build，且未执行发布后处理。资源图集仅约 0.79 MB，无额外 UI 运行库、模拟器片或 dSYM 混入；原生 UI 不会自动移除编译插桩或发布符号。
- Release 开启发布后处理、符号裁剪和 whole-module `-Osize`，显式关闭覆盖率；IPA 工作流改从 Archive 打包，dSYM 来自同一 Archive。Debug 覆盖率保留。新增 `--require-release`，拒绝覆盖率/调试段、本地符号未裁剪及模拟器平台；App/Widget 和内嵌代码分别校验签名。
- 同源码设备 Archive 的 `-Osize` / `-O` 候选分别约 6.22 / 6.32 MB。指定 iPhone 17 Pro / iOS 26.5 / Xcode 27 上，5 次离线演示测量：84 门课反复解析并生成快照 100 次，均值 0.051577 / 0.051873 秒；响应式首帧 1.110848 / 1.362457 秒。测试构建只为隔离 fixture 显式启用 DEBUG 条件，仍使用 Release 优化、无覆盖率；场景不含真实网络与 Sentry 启动，不能推断所有真机功能或声称统一提速。未见这个负载退化，选择体积优先模式。
- 最终正式标识 IPA 为 `build/deliverables/1.0.4-7-optimized/AHUTong-1.0.4-7-optimized-resignable.ipa`：6,223,741 bytes（较 #145 −34.7%），解压 13,390,502 bytes，主程序 12,184,000、Widget 309,568 bytes；SHA-256 `e570ab74fc29dbc0d5438b5e456f113fb4b7e910e63c20c03debc1e3f2cae5e8`。只作完整临时签名及共享声明，仍需授权重签才能安装。独立保留匹配 dSYM：App `FBB25FD4-AC78-3FC5-B73F-D573BE959173`，Widget `6DFCDA48-F841-3467-96DE-645C37182F02`；新符号尚未上传 Sentry。
- 按用户要求彻底移除校园码最终加载失败的业务信号，保留崩溃、共享权限/写入和会话续期诊断；新过滤器丢弃退役/未知分类，删除旧专用离线缓存并启用 v2 目录。关闭自动会话、MetricKit、客户端统计报告等，不设置用户标识；当前无法准确统计日活/留存。账号、凭据、课程、邮件、二维码、任意错误正文和栈变量不进入事件；隐私文案及数据映射同步收窄。
- 验证：31 项 Python 签名/打包回归通过，49 个 UI 入口恰好分组一次；隔离的 Release 优化构建 548 单测中 547 通过、1 显式联网收件跳过，6 条 UI（协议拒绝、4 条快捷指令、启动测量）全通过。最终无 DEBUG 的普通 Release 也以单元宿主隔离通过同样 548 项（547 通过、1 跳过），见 `final-unit.log` / `final-unit.xcresult`。日志/结果位于 `build/optimized-20261025/`，`comparison-final.json` 记录精确数据，最终 Archive 与 dSYM UUID 一致。首次 CLI 默认 CommandLineTools 不含设备 SDK，改为明确 DEVELOPER_DIR 后脚本测试通过，不将环境失败当作通过。
- 保留失败证据：首次直接使用旧 Debug xctestrun 只跑了既有用例，新性能方法未执行；改为直接构建测试。随后普通 Release 未启用演示账户，导致两条快捷指令断言失败，并误触该模拟器真实协议/体验状态；已告知用户，真机未受影响。RootView 现仅在隔离存储下接受重置/模拟同意参数，Release 单元宿主也先隔离；显式 DEBUG fixture 的优化构建复验通过。最终无 DEBUG 的设备归档曾出现 Bool getter 缺少 return，修正后 Archive 通过；不隐藏首轮失败。
- 真机边界：已连接测试 iPhone / iOS 27.2，现有正式 App 为 1.0.4 (6)，尚未卸载、重置或安装修改。Xcode 开发账号与证书有效；最初误将证书个人标识当 Team ID，已更正。实际团队无法注册他人所属的正式 App/Widget 标识，自动签名回退的通配描述文件不授权 App Group；不能用缺少共享组的导出冒充小组件修复。准备独立验收 App/Widget 和共享组时，自动审批审查要求用户明确授权创建 Apple Developer 资源；已提出具体授权问题，安装/实机验收仍待完成。
- 最新约束：用户随后撤回独立验收资源授权，明确“不允许创建，就一个 id”。独立标识注册命令此前被审批拦下、未执行；没有创建新 App ID/App Group 或并排安装。已删除该方案的五个本地生成配置/测试文件；正式工程仍为 `com.openahu.ahutong`、原有 Widget 扩展 `com.openahu.ahutong.widget` 和原共享组，不更换生产标识。只读复查确认无遗留 xcodebuild 任务，手机现有 App 仍为 1.0.4 (6)。后续只允许使用现有标识的有效签名进行覆盖验收；小组件共享授权未解决，不再等待或重新请求创建独立标识。

### E-20261026-01：最新 Android 源码审计、原生小工具与测试精简

- Android 固定 `680abc29e2df7da0c2c650e2f88c8355327bc01d`（master/develop，3.4.7-beta1）；仅只读对照。差距与优先级见 [审计](2026-10-26-android-gap-audit.md)，新增业务不标为已移植。
- 小工具改用系统分组 List、searchable、NavigationLink、Toolbar；保留首页已固定的入口及 14 个现有目的地。删除首页布局读取/减法过滤、自绘小组件预览和不可达占位分支；小组件指引用原生 Form、半高/全高 sheet、完成按钮和 ShareLink，保留同步及不含账号/课程内容的安装检查。
- 删除无调用的原型 APIClient、旧 HEAD 验收分支与报告；生产招行 WebView 及敏感凭据/外跳限制保持。删除 49 个有明细依据的冗余/过期单测，6 个有效招行安全回归移到现有 XCTestCase；修复一项错放在 Stub actor 内、不被发现的续期测试。源码预算 500 / 500；见 [逐项测试审计](2026-10-26-test-audit.md)。CI 添加预算检查，UI 大链路按功能拆分，67 个 UI 方法恰好分片一次。
- 本机证据均在 `build/tools-native-20261026/`；Xcode 27.0 / 指定 iPhone 17 Pro / iOS 26.5，隔离演示数据、默认减弱动态效果关闭，没有真实充值。`native-smoke.xcresult` 为原生工具搜索、首页固定入口、Widget 引导、电话本及大字体首轮证据；`services-ui.xcresult` 保留旧网格/按钮几何假设的首次失败，复验见 `final-ui.xcresult`。脚本回归 `scripts-xcode.log` 为 31 项全通过，覆盖真实 Mach-O、资源签名、裁剪及模拟器二进制拒绝。
- 最终 `final-unit.xcresult` 实际发现并执行 500 项 Swift 单测：499 通过、1 项显式 Sentry 收件按设计跳过，0 失败；错放 actor 的续期测试已实际执行通过。`final-ui.xcresult` 30 项全通过，连同此前成功专项共 45 个不重复 UI 方法通过；67 项分片完整性检查通过，不声称本轮运行全部 67 项。
- Release `final.xcarchive`（无 DEBUG、无覆盖率、-Osize）和 App/Widget 双 dSYM 已在本地生成。IPA `build/deliverables/1.0.4-8-native-tools/AHUTong-1.0.4-8-native-tools-resignable.ipa` 为 **6,180,767 bytes**，解压 **13,308,198 bytes**，SHA-256 `51f18dc6a75729ccfdfcc4dcf19be45e3390e37b2d8484e99e427f2c65be6967`；比 #145 小 35.2%，比 build 7 小 42,974 bytes。打包门禁确认 arm64 iphoneos、Release 裁剪、扩展/版本/共享声明与内嵌代码签名。dSYM 独立保存，未上传。
- 模拟器预览是同源码构建的 Simulator App；设备 IPA 不能直接在模拟器运行。真机安装和 Widget 共同组授权依旧待验，不以模拟器通过替代；保留正式 App/Widget 标识，未创建资源或卸载 App；后续预览/测试使用隔离存储，此前误用 Release 演示参数影响协议状态及保护修复已记录在 E-20261025-02。按用户要求，没有推送、合并、Actions 触发或 AIO gitlink 更新。AGENTS.md 已记录原生 UI、简洁实现、风险测试、500 Swift 单测、数据隔离与指定模拟器规范。

### E-20261026-02：双列工具页、考勤、必吃榜与验证码续期

- 用户明确否定系统分组 List，改用紧凑双列卡片，目标默认字号一屏呈现 16 个服务。仍使用原生按钮、搜索、导航及 Widget Form；不自绘系统 Tab Bar。具体契约、实现与 APNs 评估见 [本轮记录](2026-10-26-campus-services.md)。
- 教务考勤从 ADWMH 应用列表和受控 CAS 回调获得内存 JWT，只读分页；状态筛选、详情、实际缺勤日期及一次 401 重取。必吃榜只请求公开聚合，不携带学校身份或上传账单；周期/校区筛选、排行、窗口详情、置信说明及系统图表已实现。暂不包含食堂足迹及众包。
- 对照 Android `680abc29` 修复 iOS 仅尝试一次 OCR 的差异：最多 5 次新图，仅重试无效验证码结果/校方验证码拒绝；10012、网络及服务异常立即停止；Cookie 随图轮换，校园卡隐藏登录总预算 90 秒。保持凭据和教务会话，不自动重放支付请求。
- 最终单元验证 `campus-final-unit.xcresult` 实际发现/执行 500 项：499 通过、1 个原有 Sentry 收件 opt-in 跳过、0 失败；`-Osize` 编译与新推荐项无 rank 契约也已通过。新增 10、删减 10 的逐项依据见测试审计，不将固定文案断言都称作“过期”。UI 方法当前 73 项恰好分片一次。
- 教务考勤真实账号、实机偶发 OCR 与过期恢复仍待复验。必吃榜初期命令行 IPv4/TLS 失败后继续排查，Apple URLSession 和 IPv6 成功；同一客户端/模型在 iPhone 17 Pro 模拟器运行时实际获取 week/all 50 条与 month/longhe 34 条，食堂/时段/推荐项均解码通过，见 `canteen-live-simulator.log`。保持 HTTPS 校验，UI 截图为演示数据。
- 相关 UI 共 20 个不重复方法通过：初轮 20 项保留 3 个原生辅助功能/几何旧假设失败，修正后的 6 项专项全通过；最终隐私说明另以 7 项同意状态单测和 1 项首启 UI 通过，合计 21 个不重复 UI 场景。73 项分片完整性验证通过，不冒称全部运行。脚本 31 项通过。
- 考勤课程标题使用明确的系统主文字色，日期/地点保留次要色，避免标题继承整行灰色；`contrast-ui.xcresult` 的考勤筛选/详情复验通过，最终颜色在同源码模拟器构建现场查看。最终 Release 为 `primary-color-final.xcarchive`，打包门禁日志 `primary-color-package.log`；不为颜色添加静态镜像测试。
- 当前没有 APNs；已记录公开公告订阅服务端、device token、通知授权及现有 App ID 推送能力的后续方案，未创建新资源。Actions 暂停，不推送或合并，不更改 AIO gitlink。

- 最终本地候选为 1.0.4 (9)：`build/deliverables/1.0.4-9-campus-services-final/AHUTong-1.0.4-9-resignable.ipa`，6,285,901 bytes，解压 13,526,182 bytes；比 #145 小 34.08%，比此前 build 8 增加 105,134 bytes（新增两个业务及续期修正）。SHA-256 `af261316b375a16582841ad3bca36899e7aa7b2a5b2cb5000b61d82ab9727d61`。Release/arm64/扩展/版本/内嵌签名门禁通过，App/Widget dSYM UUID 一致，独立保存未上传。模拟器是同源码单独构建，设备 IPA 仍需开发者重签，实机安装和共同组授权未验。

### E-20261026-03：按参考图确定分类卡片及短按压反馈

- 按用户提供的 Android 截图保留四个分类标题，16 个真实服务按双列浅底细描边卡片呈现；学业组教务考勤位于组末。保留系统搜索、导航、TabView 及 Widget Form。默认字号首屏可见 15 个服务，学习资料和小组件指引滚动可达；不挤压分类标题或用户字号。
- 按压反馈从设置域抽到 `Core/DesignSystem/PressFeedbackStyle.swift`，工具、设置及开发者页面共用轻触觉、高亮、透明度和 0.12 秒短缩放。减弱动态效果禁用缩放及动画，非动态反馈保留；详情进出交给系统转场。没有新增动画依赖或定时器。
- `categories-final-build.log` 构建通过；指定 iPhone 17 Pro / iOS 26.5 的 `categories-ui.xcresult` 实际执行 17 项全部通过，覆盖工具双列与末尾入口、搜索/空结果/返回、5 个新业务场景、电话本及大字号、Widget 引导、设置/开发者共享反馈、真实系统减弱动态效果及外部跳转根导航。测试后减弱动态效果恢复关闭，默认字号和浅色预览恢复。
- 预览截图 `build/tools-native-20261026/tools-categories-light.png`，短按压/系统转场录屏 `tools-card-motion.mp4`；数据为隔离演示内容。此前“一屏内全部入口可点”的 UI 假设按新设计修正，UI 总数仍 73 且每项分片一次，Swift 单测仍 500；未为布局和颜色新增镜像单测。
- 用户明确今天下午 OCR 失败与 OpenAHU 服务短时故障有关，随后恢复；按现场反馈记录，不将这次事故归为已证实的 iOS 续期缺陷。Vision OCR 已由用户安排另一 agent 探索，本轮未修改识别器或对方工作区。
- 此切片只更新源码、文档和模拟器预览，未重新生成设备 IPA；E-20261026-02 的 1.0.4 (9) 仍是先前归档候选。Actions 继续暂停，没有推送、合并、新增签名资源或 AIO gitlink 变更。

### E-20261027-01：服务器 OCR 保留及最新 UI 设备包

- 用户确定暂时使用服务器 OCR。源码只采用 `RemoteCampusCaptchaRecognizer`，`CampusWebAuthentication` / `CampusCardLoginFlow` 默认均为远端实现，App 未接入 Vision。将此约束记入 AGENTS.md；本轮没有改变认证业务代码。
- App/Widget 版本保持 1.0.4，构建号从 9 同步到 10。使用 E-20261026-03 已验收的分类卡片、共享按压反馈及前一切片的教务考勤、只读必吃榜和有界验证码挑战，补齐此前 UI 只存在模拟器的设备包缺口。
- `build/candidate-20261027/archive.log` 的纯 Release iphoneos Archive 成功，无 DEBUG、无覆盖率，保持 -Osize 和发布裁剪；`package.log` 确认版本/扩展/Intents/共享声明、发布裁剪、App/Widget/内嵌代码签名均通过。App/Widget dSYM UUID 逐一匹配。功能源码沿用此前 500 项单测（499 通过、1 个显式 Sentry 收件跳过）及分类 UI 17 项通过的证据；本轮仅版本和文档变动，没有重复整套测试。
- 最终 IPA `build/deliverables/1.0.4-10-native-tools/AHUTong-1.0.4-10-resignable.ipa`，6,289,426 bytes，解压 13,542,792 bytes；直接读取本地原始 #145 的 9,536,231 / 35,471,706 bytes 比较，分别减少 34.05% / 61.82%。SHA-256 `7a4fd8db81ccb918a1cee6eb0076bd4221a724c8a970119495ab72eb3a525ce8`。manifest 与 dSYM ZIP 独立保存在同目录。
- 本地临时签名仍需开发者重签；物理安装、Sideloadly 最终共享授权和真实账号考勤未验。未创建资源、未改生产标识、未推送/合并/触发 Actions，未上传新 dSYM，AIO gitlink 不变。去除插桩和局部优化不等于已量化相对 #145 的实机整体提速。

### E-20261027-02：1.0.5 真机覆盖安装

- 按用户要求将 App/Widget 同步提升为 1.0.5（11），本地 Release Archive 成功；发布裁剪、扩展/版本/Intents 结构及逐个内嵌代码签名检查通过。业务源码沿用上一切片，无重复整套测试；Swift 单测预算仍为 500/500。
- 使用现有开发证书和包含测试设备的有效描述文件签名，未创建 App ID 或 App Group。首次安装被系统以旧包 application-identifier 带团队后缀为由拒绝；沿用系统报告的已有签名标识重新签名后，覆盖安装成功。正式 Bundle ID 保持不变，未卸载、清空数据或使用演示参数。
- `build/candidate-20261027/install-1.0.5-compatible.json` 确认安装成功，`physical-after-1.0.5.json` 确认版本 1.0.5（11）且数据容器可访问；`physical-launch-1.0.5.json` 确认正常启动。登录状态和业务内容仍由后续实机验收确认，不把启动成功记成业务全量通过。
- 已签名 IPA：`build/deliverables/1.0.5-11-device/AHUTong-1.0.5-11-device-signed.ipa`，6,319,236 bytes，解压 13,631,396 bytes，SHA-256 `75d625ed1698cdb6dd8d739cea760d03f984db117d848f5b0d046038c9012959`。匹配 dSYM 独立保留，未上传。
- 用户明确先覆盖安装、小组件下版处理。现有 profile 不授权 App Group，本次签名未声明未经授权的共享权限，Widget 扩展仍在，设备返回共享组为空；未通过完整 Widget 共享签名门禁，不宣称小组件已修复。Actions 继续暂停，无推送、合并或 AIO gitlink 改动。

### E-20261027-03：恢复推送与云端 IPA 构建

- 用户随后明确要求将当前改动推送，让 Actions 生成可替代 #145 的最新 IPA，恢复本次推送与构建授权。沿用 PR #12 的维护分支，不改 AIO gitlink，不上传本机证书、描述文件或真机签名 IPA。
- 推送内容包含 1.0.5（11）、分类小工具、教务考勤/只读必吃榜、服务器 OCR 有界重试、Sentry 收窄与 Release 裁剪。云端采用 Archive，关闭覆盖率并独立保留/上传匹配 dSYM；打包时从内到外签署框架、动态库、Widget 与 App，逐个严格验证，修复 #145 漏检资源框架签名的问题。
- 推送前：本机 Release Archive 及真机覆盖安装/启动证据见 E-20261027-02；同一 Archive 经云端打包脚本再次产出 re-signable IPA，发布裁剪和权限声明门禁通过。31 项脚本测试全部通过，Swift 单测预算 500/500，73 项 UI 测试恰好分片一次，`git diff --check` 通过；业务单测和 UI 沿用前一切片的实际结果。
- Actions 产物是供重签的 IPA，保留原共享声明，不含开发者私钥或设备 profile；不能将打包成功等同于任何签名工具都能授予 App Group。实际运行结果、下载地址与校验值以对应提交的 Actions 及 PR 检查记录为准。

### E-20261027-04：首页全量工具与原生详情整理

- 用户明确首页保留 8 个位置，16 种工具均可选择。删除只有 10 项的 `HomeWidgetSpec` 及第二份跳转 switch，首页、小工具页共用 `ToolItem`、图标与 `ToolDestination`。旧 `phone_book` / `repository` 等 homeID 和用户排序不变；已选工具仍从库中隐藏，8 个位置用满时禁止继续添加。
- 总览课表的非本周课程仅将深色背景灰阶从 0.18 调至 0.24，浅色 0.90、文字灰阶与统一 8pt 连续圆角不变。
- 工具详情审计：下表描述最终组件边界，不将“SwiftUI 实现”等同于全系统控件。全部 16 个入口共用原生导航栈与系统返回，工具首页保留已确认的分类双列卡片。

| 工具范围 | 原生组件及本轮整理 | 保留的专用 UI |
| --- | --- | --- |
| 失物招领、成绩、考试、空闲教室 | 保留原滚动卡片、信息顺序和筛选/结果分区，使用 Picker / searchable / DisclosureGroup / 原生 Toggle 按钮及工具栏；失物发布、详情、我的帖子使用系统 Form / List / NavigationStack/sheet，删除先确认 | 成绩概览/课程卡片、考试卡片、空闲教室分区、失物帖子卡片及右下发布入口；不改服务端读写、所有权或认证校验 |
| 培养方案、考勤、邮箱、电话本、必吃榜、校园卡账单 | 已有 List / Form / 原生筛选及详情保持，共用目录与目的地 | 必吃榜图表、学校邮箱 SSO/富文本必要的 WKWebView |
| 天气、校历 | 天气原生城市搜索、工具栏与设置 Form/sheet；校历原生保存工具栏和返回 | 实况/预报图表卡片、校历缩放图片及 PhotoKit 保存权限 |
| 学习资料 | 原生工具栏、加速源 Form/sheet、Markdown 阅读 sheet；删除不再调用的 goUp 与自绘遮罩、关闭区 | 目录/面包屑与下载管理内容行仍为专用布局，文件校验/Quick Look 不变 |
| 浴室缴费、电控缴费、网费充值 | 移除重复的大标题，标题及返回由原生导航栏呈现；共享确认/核验/重试按钮采用系统样式，消除深色固定黑字 | 充值金额、余额卡片、凭据输入/确认仍沿用现有专用支付视图；本轮不改付款状态机、不执行真实充值 |

- 冗余清理主要为重复目录、重复标题/搜索/筛选/弹窗容器、资料库设置与 Markdown 遮罩；没有新增依赖或通用防御层。支付状态按钮移除固定黑字与自绘胶囊，保留操作位置、状态文案及回调，采用系统 bordered/borderedProminent 样式。单测仍为 500 项；迁移用例保留旧 ID、退休 ID 清理和新工具恢复，同一独立迁移场景内验证。UI 新增首页工具库覆盖，按“已摆放 + 可添加 = 16”检查，兼容已有首页布局；不以静态文案或常量镜像测试占用单测预算。
- 构建与测试：仅使用本机 iPhone 17 Pro（iOS 26.5），Xcode 27 / iOS 17 最低目标的 Release 配置模拟器构建通过（开启 DEBUG fixture 以隔离演示；不作为正式 Release 启动性能证据）。49 项相关单元测试通过；25 项不同 UI 用例最终通过。首轮 19 项 UI 中发布按钮因外层 screen ID 覆盖浮动按钮标识而失败，修正 ID 所在容器并在样式之后赋值后，失物详情/加载空错/发布 3 项全部复验通过；支付共享按钮改为系统样式后，6 项相关演示交互及首页目录再次全通过，不用盲目重跑掩盖失败。
- 本地产物：`build/tools-native-20261026/tools-original-layout-tests.xcresult`（49 单元 + 19 UI，首次标识失败保留）、`tools-accessibility-tests.xcresult`（8 项失物单元 + 3 UI 全过）、`payment-native-control-tests.xcresult`（6 支付 UI + 1 首页 UI 全过）；最终构建 `payment-native-final-build.log`。新增 UI 覆盖在已有 3 个首页工具时仍通过，手动验证网费充值添加、跨启动保留和从首页进入正确页面。
- 预览：`tools-original-layout-light-final.png`、`lost-found-original-layout-final.png`、`overview-inactive-dark-final.png`；对比确认深色灰底、字体与圆角，预览结束恢复浅色、标准字号和减弱动态效果关闭。模拟器保留最终同源码构建与隔离演示数据，真实账户/Keychain 不清理；没有执行真实发布、删除或充值。
- `check-swift-test-budget.py` 为 500/500，74 项 UI 恰好分片一次，`git diff --check` 通过。代码与文档仍为本地修改，本轮不推送、不触发 Actions，也未重新生成 IPA。

### E-20261027-05：首页编辑反馈与卡片细节

- 审计发现首页原先只在编辑状态的长按菜单内提供移除，未提供可见的减号或拖入移除区，也没有显式的长按/拖放触感。改用系统 onDrag / dropDestination，长按进入编辑、开始拖动、成功换位/放入及移除触发轻触觉；拖入移除区时高亮并提供 selection 反馈。编辑卡片不再触发页面跳转，保留系统拖放预览；非编辑卡片复用共享按压反馈。
- 编辑模式展示 44pt 触控范围的减号与“拖到这里移除”区域；两者均只清空首页对应位置，工具即时回到可选库，原工具功能与业务数据保留。VoiceOver 提供工具名与独立移除按钮，拖放仍使用已有稳定 homeID 与账号隔离布局存储。
- 失物招领帖子从近似直角的 4pt 调至 20pt 连续圆角，按压高亮使用同一圆角，外侧间距移到按钮外，避免高亮超出卡片边界；信息顺序、筛选、分页和读写逻辑不变。
- 设置账户卡片明确显示真实账号学号并占满内容宽度居中；体验账户保留体验名称，登录操作位置不变。
- 验证：仅使用本机 iPhone 17 Pro（iOS 26.5），Release 配置模拟器构建通过（DEBUG 隔离 fixture）。4 项 HomeWidgetLayout 单元与 10 项不同 UI 用例最终通过，覆盖拖动换位、拖入移除、减号移除、重新添加/导航及跨启动保存、16 工具目录、失物详情和设置。首轮 2 项首页 UI 因外层工具库标识覆盖内部“完成”与移除区而失败，移到标题并合并移除区的辅助功能元素后，4 项相关首页 UI 全部复验通过；未通过的首次结果保留，不盲目重跑。系统触感使用 sensoryFeedback，模拟器不提供实体震感验收。
- 产物：`build/tools-native-20261026/home-edit-polish-tests.xcresult`（4 单元 + 10 UI，首轮 2 项失败）、`home-edit-accessibility-tests.xcresult`（4 项首页 UI 全过）。目视复核长按进入编辑、失物圆角与居中学号，保存 `home-edit-removal-preview.png`、`lost-found-rounded-cards.png`、`settings-centered-student-id.png`。保持浅色、标准字号、减弱动态效果关闭和可交互的隔离演示预览；真实账号与 Keychain 保留。
- Swift 单测仍为 500/500，77 项 UI 恰好分片一次；`git diff --check` 通过。本轮未推送、未触发 Actions，未重打 IPA。

### E-20261027-06：长按松手的拖动取消崩溃

- 用户提供 1.0.5（11）的 iPhone 17 Pro 模拟器崩溃报告，确认操作为“长按后直接松手”。主线程 EXC_BAD_ACCESS 位于 AttributeGraph → SwiftUI `DragAndDropBridge.dragInteraction(_:previewForCancelling:withDefault:)`，说明系统处理拖动取消预览时访问了无效图属性。
- 源码发现 E-20261027-05 在进入编辑时将拖动源从 NavigationLink 替换成另一种视图；这一身份变化与报告中的回落预览失效一致。改为始终保留同一个 NavigationLink 与 label，编辑状态只禁用导航和调整卡片显示。仍使用系统拖放、独立减号及移除区，不引入延时或额外依赖。单次修复前自动化长按未稳定复现该崩溃，不把风险点推断写成已得到逐次复现的系统内部根因。
- 补充独立 UI 场景：连续 5 次长按松手并退出编辑、普通模式拖到无效区域、编辑模式拖到无效区域、工具库拖动取消；验证恢复导航与原摆放保留。成功排序、移除及持久化仍使用既有用例。
- 验证：仅使用指定 iPhone 17 Pro（iOS 26.5），Release 配置模拟器构建（DEBUG 隔离 fixture）通过；4 项 HomeWidgetLayout 单元和全部 12 项 Tools UI 用例通过。首页取消场景改为直接启动首页，排除工具 Tab 设置步骤干扰后，两项普通模式取消/五次长按松手再次通过。没有新增 Swift 单测，预算仍为 500/500；81 项 UI 恰好分片一次。
- 产物：`build/tools-native-20261026/home-drag-stable-source-tests.xcresult`（4 单元 + 12 UI 全过）、`home-drag-direct-home-tests.xcresult`（2 UI 全过）；修复前单次长按结果为 `home-long-press-release-repro.xcresult`，该次未崩溃。原始用户报告与修复前诊断产物保留在本机，不提交包含设备识别信息的崩溃文件。当前只确认这些复验未再出现崩溃，不声称已稳定复现并证明系统内部根因。
- 可见窗口另手动验证 1.2 秒、3 秒按住后直接松手，两次都能正常完成编辑，随后点开浴室工具并返回首页；没有执行支付。保持浅色、标准字号、减弱动态效果关闭，模拟器留在最终同源码隔离演示预览；真实账号与 Keychain 保留。本轮未推送、未触发 Actions、未重打 IPA。

### E-20261027-07：必吃榜个人记录、多选食堂与“吃什么”

- 对照最新 Android master/develop `90a0fdc`（3.4.7），复用现有只读校园卡客户端，补充账单终端字段 `locationName`。近180天个人正餐、五分钟餐次合并、常去窗口及食堂筛选使用 SwiftUI List/Form；没有持久化或跨账号全局个人账单缓存。失败不伪装空数据，不发布未读完的部分总额。
- 公开榜单新增多选食堂，校区变化清空旧食堂，修复筛选期间保留旧范围结果及 demo 不遵守范围的问题。公开 window-map 实际返回 version79 / 189项，普通 insights week/all 返回50项；额外只读探测确认 limit 上限200，该范围返回146项，因此抽取独立请求200项，避免只从前50名抽取。与既有字段兼容，没有提交生产写请求。
- “吃什么”从选中范围已命名榜单窗口等概率抽取；约3秒逐渐减速滚动后，原生结果分组展开热度排名、位置和平均每笔消费。减弱动态效果时用等待与淡入，后台/离页取消，不新增动画依赖。
- “贡献近30天记录”提供完整数据预览、独立同意和确认，默认不上传；没有移植 Android 的自动上传及空载心跳。每批400笔，失败立即停止，显示已确认进度；窗口名称补充进入待审队列。请求使用独立无 Cookie Session、拒绝写入重定向，不携带校园凭据或账号标识。隐私说明明确IP与行为规律风险，避免宣称完全匿名。配置与口径见 `docs/operations/canteen.md`。
- iOS 仓库检查时没有 `CANTEEN_WRITE_KEY`，用户表示会配置同名 Secret；两个打包 workflow 已接入只写临时 xcconfig 的注入脚本。本地缺钥构建只禁用真实提交，不影响记录/抽取。没有推送或触发 Actions。
- 单测预算审计：移除 `CampusCardInteractionTests.testFirstQRCodeLoadCanRestoreCampusCardSessionSilently`（同样输入/调用/断言由 ExpandedQRCode 用例覆盖且额外验证余额）；移除简单 QR Envelope 解码用例（QRCodeClient 首方请求用例已穿过相同解析并验证结果）；移除直接比较 `validWeeks` 常量的用例（clamped边界与完整周次映射回归保留）。新增3项独立单元覆盖正餐去标识提取、餐次合并、分批失败停止，仍为500/500。
- 本地验收：iPhone 17 Pro（iOS26.5）Release 配置模拟器构建（DEBUG 隔离 fixture）通过；全量500项 Swift 单测为499通过、1项既有 Sentry 实发验证按需跳过、0失败。12项 CampusLife UI 在最终交互修正后的同一次完整运行中全部通过，覆盖单选/多选、抽取结果、离页取消、个人记录/贡献预览和空态/失败重试。修正原生开关的自动化点按位置，补充结果自动滚动及离页立即取消/清理。没有新增跳过项，88项UI恰好分片一次。
- 最终产物：`build/canteen-20261027/canteen-ui-acceptance.xcresult` 为12项UI完整全绿；扩展200项范围后，`canteen-expanded-pool.xcresult` 的全量500单元（499通过/1项既有Sentry实发验证跳过）与2项抽取UI也全部通过。旧排查产物仅保留本机，验收引用这两份最终结果。
- 可见窗口手动检查个人记录、抽取结果、深浅色与减弱动态效果；专项后恢复浅色、标准字号、减弱动态效果关闭，留在“吃什么”可交互预览。截图为 `my-records-light.png`、`draw-result-light.png`、`draw-result-dark.png`，均是隔离演示数据。另尝试普通启动复用该模拟器既有会话，目前停在登录页，未代输账号或接受协议；因此真实个人账单与贡献未验，不将 fixture 视为生产提交成功。
- 两个 workflow 与 project.yml 的 YAML、Info/Privacy plist、差异空白检查通过；构建配置用假密钥实际执行 `-showBuildSettings` 确认 xcconfig 注入，脚本未打印密钥或编码。PrivacyInfo 补充未关联身份、无跟踪的消费历史用途。没有推送、触发 Actions 或重打 IPA，AIO gitlink不变。

### E-20261027-08：固定模糊顶栏与系统动效

- 课表将原实色顶栏布局改为 ScrollView 的顶部 safeAreaInset，保留周指示器及共用操作胶囊的位置，使用系统 bar 材质，让课程能滚动到模糊栏后方；小工具和设置继续使用系统导航栏。没有放开顶栏跟随滚动。
- 首页下拉刷新触发一次 phaseAnimator 轻缩回弹，覆盖完整课程状态区，包括没有聚焦课程的情况；动画独立于网络完成时机，不增加人为刷新等待，也不因取消或错误停在缩小状态。
- 共用原生 numericText 过渡与等宽数字，用于首页课程倒计时、校园卡余额、当前温度/体感、账单汇总与必吃榜个人统计；只对实际数值变化做过渡，不伪造中间金额，也不对账号标识加数字滚动。天气同一查询刷新保留已显示快照，让新温度到达后直接过渡，刷新状态单独控制重复请求/按钮；切换地点仍显示加载，失败仍显示原有失败态。减弱动态效果时禁用数字滚动、缩放和页面淡入。
- 主入口仍是系统 TabView / UITabBar，各 NavigationStack 到达时短淡入；不替换底栏、不接管 SwiftUI 内部 UIKit delegate。保留选中周及小工具/设置离页后回根页面的既有修复。
- 必吃榜删除列表顶部的两个重复入口，使用原生 ToolbarItemGroup 在右上角显示我的记录/吃什么/刷新三个图标，保留中文 VoiceOver 名称及稳定自动化标识；“帮我选一家/再抽一次”使用原生 borderedProminent 按钮和居中文字。
- 本地 iPhone 17 Pro / iOS26.5，Release 配置（DEBUG 隔离 fixture）构建成功：全量500项单元为499通过、1项既有Sentry实发验证按需跳过、0失败。首轮17项UI中15项通过；2项新增首页回归误用受灰度控制的编辑按钮作为断言，改为始终存在的原生搜索栏后，二次6项UI全部通过，并额外覆盖原生返回手势、页头按钮、快捷指令往返和连续5次长按松手；两轮共21项独立UI的最终结果通过。Swift单测预算仍500/500，90项UI恰好分片一次，diff空白检查通过。
- 证据位于 `build/native-motion-20261027/native-motion-acceptance.xcresult`（全量单元与15项已过UI，包含上述2项后已修正的断言失败）及 `native-motion-navigation.xcresult`（6项最终全绿）；后者原生页头截图已导出到 `header-attachments/`，`home-latest.png`为同源码隔离演示截图。
- 最后追加天气刷新可见性验证：在原有定位首载测试的同一生命周期中检查后续同地点刷新，保留首载选择定位城市及提示的断言，并观察刷新期间没有空快照；没有新增测试方法，未塞入不相关场景，预算仍500/500。最终完整500单元再次通过（499通过、1项既有Sentry实发验证按需跳过），见 `native-motion-final-units.xcresult`；天气既有8单元与3项首页/紧凑天气UI也全部通过，见 `weather-retained-refresh.xcresult`。本轮累计22项独立UI最终结果通过。
- 用户解锁后完成可见窗口验收：上滚课表可见课程颜色经过固定顶栏的系统模糊，深色同样可读；主入口切换录屏的连续帧确认新页面淡入；必吃榜三个工具栏图标共用系统胶囊，抽取按钮文字居中且约3秒后正常呈现排名/均价。临时开启减弱动态效果检查首页刷新与导航可用，已恢复浅色、标准字号和减弱动态效果关闭；专项后模拟器恢复首页可交互预览。
- 预览均为隔离演示数据：`schedule-blur-scrolled.png`、`schedule-blur-dark.png`、`canteen-toolbar.png`、`draw-centered.png`；`home-tab-motion.mp4`为从原始录屏截取的7秒首页刷新/切换片段，原始`native-motion-preview.mp4`与提取帧留作本地证据。真实数据和Keychain保留，没有实机操作、充值或真实贡献。没有提交/推送、触发Actions或打包IPA，AIO gitlink不变。

### E-20261027-09：迁移当前工作副本并移除首页编辑灰度

- 用户明确要求将本轮工作副本迁至 AIO 主目录的 `iOS/`。当前代码位置为 `/Users/himekawa/Projects/AHUTong/iOS`，分支 `codex/ios-native-motion`；Git 元数据迁至 `.git/modules/iOS`，SDK/Rust 子仓引用一并修正。迁移时核对全部文件系统条目、10 个本地分支、39 个已跟踪改动和9个未跟踪文件；原有工作区改动与 Git 记录一致。构建产物、本地配置一并保留，其他历史任务工作区未清理；AIO index 不变。
- 首页编辑是基础功能，按用户要求彻底删除 iOS 的 `home_edit` 灰度功能、分桶、远端请求、状态模型及通知；首页长按/拖放与小工具页原生编辑按钮直接可用，不依赖网络或启动覆盖。`ReleaseOperations.swift` 保留仍在使用的日志脱敏与版本诊断。
- 删除4项灰度专用单元测试，Swift 单测降至496/500。既有首页工具库、排序/移除、长按松手、取消拖放和原生页头 UI 测试改为普通演示启动，不再使用强制开启参数；搜索空态断言保留默认编辑入口。旧 `debug.gray.*` 仅在遗留偏好清理及其回归中出现，不参与功能决策。
- 新路径首次构建因 Swift Package 缓存仍引用原路径的 XCFramework 而中止；已修正2个本地 artifact 路径，未改变依赖版本。随后 iPhone 17 Pro / iOS26.5 的 Release 配置（DEBUG 隔离 fixture）构建成功，全量496单元为495通过、1项既有Sentry实发验证按需跳过、0失败。
- 14项相关UI的最终结果通过：首轮13项通过，空搜索新增断言误把系统搜索模式隐藏工具栏按钮视为失败；删除此错误断言，保留空态与无匹配工具的检查，专项复验通过。默认编辑入口、16种目录、长按松手、取消拖放、排序、移除/重加、原生页头和设置外部跳转已验。测试不再传灰度参数。证据为 `build/no-gray-20261027/no-gray-final.xcresult` 及 `search-empty-final.xcresult`；90项UI恰好分片一次，diff检查通过。
- 历史验收记录中有关灰度的描述仅反映当时行为，当前行为以本条为准。模拟器已恢复不带灰度参数的可交互预览，默认编辑入口截图见 `build/no-gray-20261027/tools-default-edit.png`。不推送、不触发 Actions，不更新 AIO gitlink。

### E-20261027-10：1.0.5（12）本地打包与实机覆盖安装

- 按用户要求保持显示版本1.0.5，本次Archive仅通过 `CURRENT_PROJECT_VERSION=12` 区分构建；源码工程版本仍1.0.5，不提升1.0.6、不推送或触发Actions。用户验收后再推进下一版本。
- 在新目录 `iOS/` 从当前完整工作区执行正式Release设备Archive；没有DEBUG/演示编译条件。设备arm64主App/Widget已裁剪，无覆盖率或内嵌调试数据；Siri动作、Widget配置元数据及扩展结构检查通过。已有496单元与14项UI最终回归证据见E-20261027-09，本轮未重复运行。
- 沿用之前成功安装的描述文件与开发证书，签名entitlements逐项与旧包一致；先签内嵌框架，再签Widget和主App，并逐个严格验证。没有创建标识、共享组或更改生产Bundle ID。
- 安装前手机为1.0.5（11），覆盖后devicectl确认为1.0.5（12），正常启动且随后进程查询确认存活；没有卸载、清空、传演示参数或替用户接受隐私协议。真实登录状态、动画手感及真实查询等待用户验收；未执行充值或贡献写入。
- 产物为 `build/deliverables/1.0.5-12-device/AHUTong-1.0.5-12-device-signed.ipa`，6,438,628字节，SHA256 `e27d442e9fd208c49c6e13d9641ce8fa48ea01dbf3b453964ff9d5cfc4cd0b16`。App/Widget dSYM UUID均已匹配并独立保存，没有上传新符号。
- 已知边界保持：现有签名不含App Group授权，Widget共享按用户决定留待后续；本机未配置必吃榜贡献密钥，真实贡献停用，公开榜单、个人记录及抽取仍可测试。详细清单与安装记录见该目录manifest及 `build/device-acceptance-20261027/`。

### E-20261027-11：首页自动刷新与系统深色导航

- 根据1.0.5（12）真实验收反馈：首页概览使用系统 `TimelineView(.everyMinute)` 推进本地时间，倒计时不等待网络；进入页面/回前台立即校准，午夜切换当天课程及教学周。前台可见期间课表/周次每轮完成后等待60秒再检查，网络尝试间隔至少60秒；失败尝试也节流。手动下拉刷新不受该间隔限制。
- 校园卡余额收起时每15秒检查，距离上次尝试至少30秒才发起读取；不取消正在完成的同类请求。二维码优先取消余额时，将余额从加载中恢复为已有缓存或空闲；前台恢复/失败回退可再次查询，旧响应不能覆盖新余额。校园码展开后每15秒检查更新，成功取码后再读余额；失败保持显式重试或下一次前台恢复，不无限重试。
- 首页天气启用时按10分钟节流，随首页60秒周期检查，保留同位置缓存；下拉可立即刷新。以上周期均受页面和前台生命周期管理，网络耗时可能延后下一轮；不在后台保持轮询。
- 深色通用底色与设置页共用 `systemGroupedBackground`；iOS26+课表固定顶栏改用 `safeAreaBar`，系统自动管理滚动边缘透光，iOS17–25仍使用 `safeAreaInset` + `.bar`。移除 `AndroidScreen` 隐式隐藏导航栏的副作用，仅首页、课表、登录/引导根页显式隐藏；16种工具通过共享路由保留与必吃榜相同的系统行内标题，由系统协调返回及右侧按钮。
- 在当前路径 `/Users/himekawa/Projects/AHUTong/iOS` 开发，保留既有改动。本机唯一模拟器为用户指定的iPhone17Pro/iOS26.5，减弱动态效果关闭。500项Swift单元执行：499通过、1项原有显式授权Sentry发送测试按原设置跳过、0失败；新增4项独立回归覆盖分钟倒计时、午夜换周、慢余额复用、取消后失败恢复。天气测试补充10分钟边界；未合并测试规避上限。
- 8项UI全部通过，覆盖引导、原生返回手势、校园码优先/重试、有课/无课首页刷新、原生页头操作及课表固定顶栏。证据：`build/home-refresh-native-20261027/acceptance.xcresult`；同目录保存首页/课表/小工具/设置深色截图，以及成绩和必吃榜系统标题对照。截图为隔离演示数据，未将其视作真实账号查询通过。
- 正式Release设备Archive为 `build/home-refresh-native-20261027/AHUTong-1.0.5-13.xcarchive`，无DEBUG/演示编译条件；App/Widget均1.0.5（13），逐项沿用12的描述文件和entitlements，内嵌签名、扩展结构、Release裁剪与dSYM UUID匹配检查通过。IPA `build/deliverables/1.0.5-13-device/AHUTong-1.0.5-13-device-signed.ipa` 为6,444,900字节，SHA256 `6cb51a3f3bcf30fc63e81a2de3a6ab2cfccfe059f14bfc5ab7059422b2b29ccc`。显示版本仍1.0.5，源码工程构建号不改，仅Archive参数指定13。
- 真机安装前12、安装后13，同一Bundle ID保留数据覆盖；正常启动不传测试参数，最终进程23714存活，Device Hub真实屏幕确认必吃榜内容可见。首次命令启动进程以退出码0结束，未发现新的主App崩溃报告，诊断记录保留；不将首次启动命令成功单独视作稳定性验收。指定模拟器另以已有真实会话正常启动，首页倒计时自然按分钟变化（观察到1小时41分→1小时39分），余额可见，无手动刷新或重新登录。`live-clock-before/after.png`仅保存在被忽略的本地构建目录，不提交真实账号截图；模拟器已恢复可交互的真实会话首页、减弱动态效果关闭。
- 现有签名无App Group和本机无必吃榜写入密钥的边界保持；未新建标识、改变生产Bundle ID、充值、提交真实贡献、推送或触发Actions，AIO gitlink不变。真实账户刷新持续性仍需用户继续实机验收。

### E-20261027-12：Keychain 核实、必吃榜精简与贡献配置安全

- 审查 `CredentialStore`、`CampusSessionStore` 和 `KeychainSecureStore`：生产默认适配器通过 Security 的 `SecItemAdd/Update/CopyMatching/Delete` 存取账号凭据及 Cookie，使用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，不启用 iCloud 同步，也没有逐次 Face ID 限制。官方登录校验成功后保存；WebView 使用非持久 website data store，GuiXu 初始化关闭会话落盘。未读取真实密码或导出用户 Keychain；现有非生产 fixture 的真实 Keychain 往返测试通过。课程缓存和普通偏好不在此凭据存储范围内。
- 榜单、我的记录及吃什么共用 `CanteenFilterButton`：左侧显式 `Color.primary`，右侧值和箭头使用主题色。目视发现层级 `.primary` 在原生 Button 内仍可能呈主题色，最终改为明确系统正文色并重建；最终深色截图 `build/canteen-polish-20261027/ranking-final-dark.png` 已确认修正。删除常规榜单的底部说明及重复热度解释，保留日期、样本和统计数据。
- 我的记录的贡献入口移至右上角原生上传图标，贡献预览的确认上传也使用系统导航栏按钮；移除记录页底部贡献按钮和重复说明。逐次预览、独立同意、数据字段/IP/撤回限制保留在预览中。无密钥、无记录、演示数据或提交中仍不允许上传，未发送任何真实贡献。
- 仅查询 GitHub Secret 名称，2026-10-27 仓库尚未列出 `CANTEEN_WRITE_KEY`。两个本地 workflow 已通过 Runner 临时 xcconfig 注入；本轮脚本在写入前建立0600权限，并为 Base64 派生值注册 CI `add-mask`，避免仅遮蔽原 Secret 却泄露构建编码值。3项独立 Python 测试覆盖文件权限及输出、CI遮蔽和缺省停用。配置步骤与客户端密钥可提取的限制见 `docs/operations/canteen.md`；没有接收、读取或写入真实密钥。
- 定向14项 Swift 单元测试和7项必吃榜 UI 测试全部通过，0失败/0跳过，结果为 `build/canteen-polish-20261027/acceptance.xcresult`；全项目 Swift 单元方法总数仍为500。最终正文色修正后再次构建成功并在指定 iPhone 17 Pro 模拟器保留数据覆盖安装、目视检查；右上角贡献入口和确认上传截图分别为同目录 `records-final-dark.png`、`contribution-final-dark.png`。未将演示数据当作真实账单或生产写入验收。
- 性能静态审计列出三项候选：合并首页刷新前后无变化的 Widget 快照写入/时间线重载；个人记录筛选、分组和汇总在输入变化时计算；课表按数据/周次/偏好变化复用派生布局。尚未为这些候选修改实现或声明提速比例，下一步以真机 SwiftUI Instruments/Time Profiler 定位耗时，保留原生材质和隐私边界。
- 本轮仍在 `/Users/himekawa/Projects/AHUTong/iOS` 开发。实机现有1.0.5（13）是上一切片产物，尚不包含本轮必吃榜调整和贡献密钥；未重新打设备IPA、安装真机、推送、触发Actions、提交生产贡献或更新AIO gitlink。添加 Secret 本身不会更新已安装包，须等待用户授权的下一次构建。

### E-20261027-13：贡献配置、1.0.5（14）真机覆盖与实际包安全审计

- 用户已在 GitHub 配置 `CANTEEN_WRITE_KEY`，只读元数据确认名称及更新时间；GitHub不提供Secret原值读取。为完成用户要求的本机打包，用户在本机终端以隐藏输入独立提供同一密钥，生成被忽略的0600私有临时xcconfig，没有通过聊天或命令参数传递原值。
- 本机正式Release Archive使用构建号14，版本保持1.0.5；最终Archive主App实际配置与本机输入一致，Widget Info.plist不含该密钥字段。构建日志在写入前遮蔽原值和编码值，并再次扫描确认均无匹配；源码/未忽略文件扫描未发现密钥。本轮3项配置Python测试通过，沿用同源码14单元及7UI结果；Swift单元方法总数500，未为纯构建配置重复全量运行。
- 主App、Widget和内嵌框架沿用13的既有证书、描述文件及entitlements，严格签名检查通过；App/Widget均为1.0.5（14），二进制与独立dSYM逐一匹配。产物 `build/deliverables/1.0.5-14-device/AHUTong-1.0.5-14-device-signed.ipa`，6,444,100字节，SHA256 `8e30983c592ba9729b24fad064dbf1a7c1f49d705e205b4f60674e4dcfcf9899`。
- 已在用户测试iPhone从13保留数据覆盖安装到14，没有卸载、清空或改变标识，正常启动不传演示/测试参数。Device Hub真实首页可见，主进程24379复核存活；未替用户同意贡献、未充值或上传真实记录。详细安装结果、进程和manifest在被忽略的本地构建目录；真实功能体验仍待用户验收。
- 用户进一步询问Secret泄露后，对最终IPA逐文件审计：`Payload/AHUTong.app/Info.plist`包含可离线还原的`CANTEEN_WRITE_KEY` Base64；持有IPA即可提取，不以Secret配置、日志遮蔽或Base64宣称客户端保密。未发现原值明文、CI Secret变量名或Sentry管理令牌格式；公开Sentry DSN按设计存在。此扫描不保证识别所有未知令牌，CI的管理令牌仅用于独立符号上传步骤。审计报告只记录位置和布尔值，不含密钥。
- 如果接口维护者要求密钥严格保密，当前打入客户端的方案不满足要求，需停用/轮换并改服务端保管或短期受限授权；若定位为公开客户端凭据，服务端仍必须限流、去重和审核，不能信任客户端同意及数据过滤约束。真实生产写入及密钥的服务端权限未验证。
- 既有App Group授权缺失按用户决定延期；本轮不升1.0.6、不推送、不触发Actions、不上传dSYM、不更改AIO gitlink。工作副本仍位于AIO主目录的`iOS/`，CI接线修改尚未推送。

### E-20261027-14：Android密钥实现与线上Actions泄露检查

- 只读检查Android最新master `eaf65cf7c6dc1204e889eb93408c92ef00b23c63`：发布workflow从`secrets.CANTEEN_WRITE_KEY`注入环境，Gradle生成`BuildConfig.CANTEEN_WRITE_KEY`，接口客户端附加`X-Api-Key`。源码明确承认可从APK提取，服务端限频/配额是主要防线；接口文档将写入键与管理员HTTP Basic区分。没有修改Android或提取正式APK，也未确认实际服务端部署权限。
- 用户追问最新版本防护后，确认develop也为同一提交，工程版本3.4.7（304012）；审查HTTPS、同意闸门、30分钟成功/5分钟失败节流、400笔分批及报告者随机UUID。服务端限频、配额、去重及审核仅为接口文档依据。新增静态发现：Android必吃榜共用网络诊断拦截器保留原始请求头，NETWORK环形缓冲的密码脱敏规则不遮蔽`X-Api-Key`；密钥会进入私有内存网络详情，并可能随用户选择的详细反馈提交，未验证真实附件，不等同于自动公开上传。证据为同提交的`AhuHttp.kt`、`FeedbackNetworkInterceptor.kt`、`FeedbackDiagnostics.kt`和`DiagnosticSanitizer.kt`，只读下载在本地审计目录，未修改Android。
- iOS线上最新IPA #146（run40366421271）及Archive #89（run40366421382）均为1.0.5（11），构建提交`24a7e013`；北京时间2026-10-27凌晨开始，早于用户Secret更新时间14:35。该提交的workflow不引用贡献密钥，本地14的接线与产物尚未上传。
- 实际下载并逐文件扫描上述IPA和Archive：主App均无贡献密钥配置字段，未检出本机14密钥原值/编码和Sentry管理令牌格式。扫描这两次构建及最新iOS CI（run40366426691）日志，同样无匹配；两个符号上传步骤的Sentry令牌环境变量值均已遮蔽为`***`。报告只含位置和布尔值，不含密钥，保存在被忽略的`build/actions-secret-audit-20261027/`。结论限于检查到的运行和产物，不将格式扫描等同于任意未知凭据的绝对保证。
- 当前可提取贡献密钥的产物是本机1.0.5（14），已安装但未上传；添加Secret本身不会更新历史产物。未来Actions若构建含接线的源码，也会把客户端密钥写入IPA。此次只读审查和文档更新，未触发构建、推送或生产写入，`git diff --check`通过。

### E-20261028-01：1.0.6 构建前检查与 Actions 贡献门禁

- 用户明确授权当前 iOS 检查通过后推送、触发 Actions 并提升下一个版本；App 和 Widget 同步提升至1.0.6（15）。延续现有 PR #12，不创建重复PR，不自动合并，不改AIO gitlink。
- 两条设备打包 workflow 在 Archive 前要求 `CANTEEN_WRITE_KEY` 非空且没有非法请求头字符，创建0600临时xcconfig并遮蔽派生值；Archive 后核对实际 App 配置与本次输入完全一致。缺失或不匹配时构建失败，不发布静默停用贡献的官方包。7项配置脚本测试覆盖这些边界。开发模拟器测试不依赖贡献Secret。
- 通用日志的请求头和字段规则增加 `X-Api-Key` 脱敏，使用既有独立日志测试覆盖，不增加 Swift 方法。贡献仍只发送限定字段，使用无校园Cookie的临时会话，拒绝重定向，分批400笔，需逐次预览及独立同意；没有执行真实充值或生产贡献写入。
- 指定 iPhone 17 Pro（iOS26.5）完成500项Swift单元测试：499通过、1项既有显式Sentry收件测试按设计跳过，0失败；23项重点UI全部通过，覆盖必吃榜筛选/抽取/贡献预览、校园码、首页刷新及无课、长按松手/取消拖动/拖入移除、设置外部跳转后回根页、固定课表表头及原生导航手势。未重置真实账户存储。证据：`build/release-1.0.6-20261028/acceptance.xcresult`。
- 38项Python测试全部通过、无跳过；Swift预算500/500，90项UI在CI分片中各出现一次，`git diff --check`通过。仅删除此前已记录的过期/冗余测试，没有合并场景规避预算。
- 正式iphoneos Release Archive构建成功，App/Widget均为1.0.6（15），实际配置校验通过；可重签IPA通过arm64、发布裁剪、无覆盖率/调试段、内嵌框架/Widget/App签名与AppGroup声明门禁。App UUID `CFE9D995-325B-3F2B-9468-9C26BE7867CD`、Widget UUID `80430A69-031D-3780-B988-1005B9B39258`分别匹配本次dSYM。本地Archive日志未包含贡献原值或编码。证据目录：`build/release-1.0.6-20261028/`。
- 本地验证范围内未发现新的阻断性功能问题；真实服务是否接受该密钥及真实账单提交仍需用户验收，配置门禁和fixture通过不等同于服务端真实写入成功。内置客户端贡献密钥仍可从IPA提取，Sentry管理令牌不进入App。Widget共同授权按用户决定延期；重签工具仍需正确授予相同AppGroup。
- 推送后云端完整CI、IPA和匹配dSYM以 [PR #12](https://github.com/OpenAHU/AHUTong-iOS/pull/12) 关联Checks/Artifacts为准，不以本地结果代替云端成功。

### E-20261029-01：全局背景与原生导航栏

- Android 固定参考 `c627dc28` 的 HomeBackgroundStore.kt / ThemeLab.kt：全局照片、默认50%的0–100%亮暗遮罩、清除和主题取色。iOS遵循用户系统材质约束，不迁移reduceGlassEffects。
- 实现：PhotosPicker选择后在后台以ImageIO缩图、按方向重编码JPEG并移除源元数据；遮罩只改变显示透明度。UIKit UIInterpolatingMotionEffect负责轻量双轴位移，图片超出边缘18pt、位移±12pt；默认关闭，遵守减弱动态效果及前后台/可见性。照片在本地Application Support，演示/测试独立目录；没有照片/传感器上传或额外依赖。
- 原生导航：四入口的NavigationStack身份保持稳定，以NavigationPath返回根页；工具、设置首层使用值路由，退出工具页同步结束搜索并清空查询。所有普通子页保留Tab Bar。课表使用系统导航ToolbarItem中的周选择器和RootView统一管理的ToolbarItemGroup三按钮（E-20261029-03），替代无调用的NativeTopBar、NativeHeaderIconButton与自绘玻璃容器；顶栏与小工具/设置一致，采用系统默认滚动边缘效果；移除曾试用的ultraThinMaterial/强制背景显示，避免额外灰色底层。
- 测试审计：`testNativeNavigationBarEdgeAndContentPopGestures`中要求子页底栏不可点的断言已随新需求过期，改为可点；不删除原生返回手势验证。Swift单元方法仍500/500，未为UI改动扩张或合并单元用例；新增两项独立工具导航/搜索UI回归，以及一项系统照片选择器取消回归。原“按钮可见图形框至少44pt/间隔8pt”的自绘容器断言不适用于UIKit工具栏，改为验证三个真实导航栏按钮均可点、四个周圆标可见且无“更多”菜单；触控区域仍由系统负责。
- 本机证据位于忽略目录`build/wallpaper-navigation-20261029/`：Release配置带DEBUG测试构建通过；经系统照片选择器导入3000×4500测试PNG后，输出1365×2048 JPEG为164,458字节，源图元数据标记不在JPEG中。`final-ui.xcresult`中10项重点UI全部通过（191.9秒）：三个系统导航按钮均可点、四周圆标可见且无更多菜单、圆形周次、固定顶栏/保留选中周、原生返回、外部跳转回根页、工具搜索与子页底栏、照片选择取消。普通Release设备构建通过，主题存储修正后`release-final-build.log`再次通过；`theme-regression.xcresult`追加工具栏/照片选择器两项复验通过。追加`background-adjustments-final.xcresult`本地探针通过（33.8秒），验证遮罩调节、视差开关/遮罩重启保存、取色和清除；截图见`background-adjustments-attachments`。探针依赖手工导入的测试图片，源文件仅留忽略的证据目录，不把有手工前置条件的用例纳入CI。Root与色板统一读取当前会话偏好，修复演示环境取色后未立即变色的问题。
- 限制：Simulator没有物理倾斜输入，本轮不能声称已在真机验证视差；没有创建标识、修改授权、推送或触发Actions。
- 顶栏灰色修正复验：移除课表单独的材质与强制背景显示后，`system-background.xcresult`两项UI回归通过（40.2秒），覆盖三个原生按钮/四个可视周圆标及滚动时顶栏固定；iPhone 17 Pro可见预览确认静止时使用页面背景、课程滚入顶栏时由系统提供渐变模糊，不再额外铺灰色底层。

### E-20261029-02：透明课表、扫码/身份码与天气原生视觉

- 用户澄清“不透光”是课程格子后的整块灰色底板。删除scheduleGrid的raisedSurface背景，保留课程卡片底色；不再把导航栏修正等同于课表透明。背景设置移除横向图片预览，调节通过实际页面背景查看。
- Android参考固定c627dc28：QrRouter.kt识别美团单车车牌/短链/正式URL及学习通签到URL，按构造时毫秒时间交接；雨课堂在Android也需微信重扫。iOS用VisionKit DataScannerViewController（QR、单码、标准帧率）及系统相机权限；白名单以URLComponents精确主机/路径匹配并拒绝userinfo，未知码不打开任意链接。画面与原文只在内存中，不记录或上报；离开/后台/处理结果时停止扫描。
- Android Main.kt的身份码入口使用固定淘宝H5与tbopen。iOS沿用相同入口，只做外部导航，不读取身份码或淘宝账号；未安装淘宝时打开公开网页。共享ToolItem新增identity_code，17种工具都能选择到首页8槽位，旧ID与排序保持不变。
- 天气保留当前、未来预报、空气质量、带伞提醒、逐小时和生活指数的信息顺序；改用系统多色SF Symbols、大温度字级、圆角中性卡片、空气质量Gauge及系统设置sheet。没有加入高频粒子/动画循环或新依赖，搜索/刷新与定位权限边界保留。
- 测试审计：移除AgreementConsentStore中逐字匹配隐私文案的镜像测试、GuiXu固定错误文案测试，以及已被RequiredDocumentsPersistAndCompleteConsent覆盖的可选社区协议不阻塞用例。新增三个独立ScanRoute单测覆盖学习通签名原文、美团交接时间和未知/伪造URL拒绝，Swift单测总数仍500/500；原有协议持久化、拒绝与重确认、GuiXu真实往返/迁移均保留。工具目录UI断言由16更新为17，新增相机不可用与天气原生页面两项UI回归。
- 本机验证：`scan-weather.xcresult`中22项相关单元测试及6项UI通过；`scan-weather-light.xcresult`中天气/扫码浅色两项UI通过；天气最后整理保持原雨雪雹/降水概率提示规则，`weather-final.xcresult`专项复验通过；普通Release设备构建`scan-weather-device-build.log`通过。`transparent-course-grid.png`可见课程格子间直接透出当前背景；深浅色截图分别位于`scan-weather-attachments`与`scan-weather-light-attachments`。Swift单测500/500，95项UI恰好分片一次，diff检查通过。
- 真实设备边界：见忽略目录build/wallpaper-navigation-20261029/scan-weather*；仅使用用户指定的iPhone 17 Pro。模拟器没有真实相机或已安装第三方App，不将扫码入口/路由验证写成真机跳转成功；本轮不执行真实签到、开锁、支付或身份码读取。

### E-20261029-03：恢复入口切换时的原生玻璃过渡

- 用户报告课表/小工具右上角的玻璃空间过渡消失。录屏对照：旧TabPageEntrance每次onAppear把整页从opacity 0淡入；仅移除这层仍是两个独立导航栏的交叉淡化，不能把删除修饰器视作动画已恢复。
- 最终改为RootView中的共同ToolbarItemGroup根据selectedTab驱动两个根页的右侧按钮，并以同一次原生smooth事务更新Tab选择。课表只绑定一个明确的HeaderAction完成回到本周/设置/刷新；小工具扫码sheet由根容器呈现。保留独立NavigationPath、系统TabView/导航栏、课程透明底板和周选择器宽度；工具子页使用自己的原生工具栏，不继承根页按钮。删除无调用TabPageEntrance，数值numericText动效保持。
- 使用iPhone 17 Pro / iOS26.5录屏逐帧对照：before.mp4及after.mp4中仅交叉淡化；最终morph.mp4在约18.35–18.71秒可见系统玻璃组扩张、模糊与新按钮组呈现，未添加自绘玻璃容器、matchedGeometry效果或UIKit内部代理。视频与提取脚本/帧位于忽略目录build/native-toolbar-motion-20261029/。
- shared-toolbar.xcresult中5项UI通过：原生三个按钮均可点、四周圆标和无更多菜单、所选周切Tab保留、搜索离页后清除、扫码不可用提示与关闭、子页底栏/根页返回。前述检查复用5个既有独立用例；Swift单元测试总数仍500/500。先行仅移除淡入时3项通过及单独周次复验保留为诊断证据，不代替最终结果。
- 本轮仅本地构建和模拟器验证，未推送或触发Actions；版本保持1.0.6（15）。动画受系统版本及设备减弱动态效果设置控制，不把iOS26.5模拟器结果扩大为所有真机版本已验。

### E-20261029-04：包体/诊断审计与必吃榜原生详情弹层

- 遵循本轮用户提供的 AIO 规则，新建 detached AIO worktree `.worktree/ios-size-sentry-canteen`，仅初始化 iOS 及构建必需 Rust 子模块；iOS 分支 `codex/ios-size-sentry-canteen` 从主工作区 7fc7ca1 带入当前未提交源码，原工作区未修改，未更新根 gitlink。没有版本提升、提交/推送或 Actions。
- 包体只审计：已交付 #147 IPA 为 6,391,329 bytes，相较 #145 减少约 33.0%。普通设备 Release 构建通过；主程序 12,737,608 bytes，Link Map 保留符号约 App/Swift 5.30 MB、Rust 3.03 MB、Sentry 2.90 MB。静态 SDK 不能只按资源框架占位文件算成本；进一步方案优先为 Sentry 无 UIKit 版本对比，AppMark 缩图次之，未盲目替换依赖/裁减功能。完整口径与证据见 [专项审计](../operations/2026-10-29-size-sentry-audit.md)。
- Android 仅只读对照最新 master d9e5f7486c2354acbd2440e7e5f425c383c95bf1；其诊断比 iOS 更广，包含崩溃/ANR、性能、安装日活及主动反馈。iOS 仍只有经同意启用的过滤后崩溃/共享/续期信号，关闭校园码最终失败与日活。用户选择仅审计代码、不查询实际事件，未创建令牌；历史收件不作实时统计。同步修正文档 D-007 仍称未集成第三方崩溃 SDK 的过期表述。
- 确认三个窗口详情入口原为整页 NavigationLink，统一改为 item 驱动 sheet；普通字号 medium/large，辅助功能大字号 large，系统完成按钮/拖动条，透明 Form 内容让 iOS 26+ 原生玻璃生效，iOS 17 沿用原生弹层。保留榜单筛选、抽取结果及所有详情字段，贡献链路不变。
- 指定 iPhone 17 Pro / iOS 26.5，隔离演示数据、默认减弱动态效果关闭。`build/canteen-sheet-final.xcresult`：3 项必吃榜 UI 通过，7 项诊断过滤单测通过，1 项显式联网收件按设计跳过；没有真实消费记录上传。浅色模式下复用窗口详情用例也通过（`build/canteen-sheet-light.xcresult`），深浅色截图已检查并恢复深色。首次 UI 失败为旧结果 Section 的 accessibilityIdentifier 盖过新按钮标识，移除无调用的父标识后完整复验通过，首轮证据保留。
- Swift 单测维持 500/500；95 个 UI 方法恰好分片一次，未新增测试方法。`git diff --check` 通过。截图和设备链接报告均在本 worktree 的 `iOS/build/`，不提交构建产物。

## 14. 变更日志

- 2026-10-29：只读审计包体及两端 Sentry 配置，用户选择不查线上事件；必吃榜三处窗口详情统一为系统底部玻璃 sheet，保留原状态，见 E-20261029-04。

- 2026-10-29：移除入口整页淡入，以共享原生工具栏状态与同一次Tab切换事务恢复玻璃过渡；5项UI回归和录屏验证见E-20261029-03。

- 2026-10-29：按用户澄清移除课表灰色底板与背景横向预览，新增系统扫一扫/菜鸟身份码，优化天气原生视觉；17种工具共享8个首页位置，见E-20261029-02。

- 2026-10-29：新增全局背景、遮罩/取色及可选原生视差；保留子页Tab Bar，以稳定导航路径减少搜索容器重建；课表周选择器上移并保留可视宽度，三按钮移入原生工具栏，见E-20261029-01。

- 2026-10-28：提升1.0.6（15），完成500单元/23UI/38Python及正式Release包检查，官方IPA强制注入并核对必吃榜贡献配置，通用日志遮蔽X-Api-Key；按授权推送现有PR #12并由Actions构建，见E-20261028-01。

- 2026-10-27：对照Android最新客户端密钥实现，并扫描iOS线上#146 IPA、#89 Archive及三条最新运行日志，未发现贡献密钥或Sentry令牌明文；明确线上11与本机14产物边界，见E-20261027-14。

- 2026-10-27：确认贡献Secret配置，以本机隐藏输入完成1.0.5（14）注入、签名和实机保留数据覆盖；实际IPA审计明确客户端密钥可提取，未发现Sentry管理令牌格式，服务端保密边界和真实贡献待验，见E-20261027-13。

- 2026-10-27：核实生产凭据和会话的设备专属Keychain存储，精简必吃榜说明、统一食堂选择颜色并将贡献动作移到原生导航栏；补齐CI密钥派生值遮蔽与私有文件测试，完成14单元/7UI/3Python定向验证及性能静态审计，见E-20261027-12。

- 2026-10-27：按实机反馈修复首页独立分钟时钟、前台课表/余额/天气自动刷新和余额取消状态；统一深色底色与系统工具子页标题，课表顶栏使用safeAreaBar；完成500单元（1原有跳过）与8UI回归，本地修正版1.0.5（13）见E-20261027-11。

- 2026-10-27：本地打包1.0.5（12）并保留数据覆盖安装到测试iPhone，启动与进程检查通过；等待用户验收后再提升1.0.6和推送Actions，见E-20261027-10。

- 2026-10-27：将当前工作副本完整迁至 AIO 的 `iOS/`，删除首页编辑灰度及专用测试，基础入口默认可用，见 E-20261027-09。

- 2026-10-27：统一课表模糊顶栏、首页刷新回弹/原生数字及主入口切换动效，调整必吃榜原生工具栏和抽取按钮，见 E-20261027-08。

- 2026-10-27：新增必吃榜多选食堂、我的记录、自愿贡献预览和“吃什么”原生随机抽取，见 E-20261027-07。

- 2026-10-27：根据用户长按松手崩溃报告，固定首页拖动源身份并补充取消拖动回归，见 E-20261027-06。

- 2026-10-27：补齐首页编辑的触感、减号与拖入移除区，统一失物卡片圆角并居中设置学号，见 E-20261027-05。

- 2026-10-27：首页共用 16 种工具目录并保留 8 槽位，略提亮深色非本周课程，整理原生工具详情及冗余 UI，见 E-20261027-04。

- 2026-10-27：用户恢复推送及 Actions 授权，准备将当前 1.0.5 完整改动更新至 PR #12，由云端打包流程替代 #145，见 E-20261027-03。

- 2026-10-27：提升为 1.0.5（11），沿用旧包签名标识完成测试 iPhone 覆盖安装及启动，Widget 共享授权按用户安排留到下一版，见 E-20261027-02。

- 2026-10-27：保留服务器 OCR，将最新四分类 UI 归档进本地 1.0.4 (10)；核对原始 #145 对比，IPA 体积减少 34.05%，解压文件总量减少 61.82%，Release/签名门禁与 dSYM 匹配通过，见 E-20261027-01。

- 2026-10-26：按用户参考图确定四分类双列浅底描边工具卡片，复用设置域按压反馈并保留系统转场；17 项相关 UI 全部通过，更新服务故障归因与独立 Vision 探索边界，见 E-20261026-03。

- 2026-10-26：按用户最新要求将 List 替换为 16 入口双列卡片；新增教务考勤、只读必吃榜与验证码有界重取流程，评估公告/APNs 边界。500 项单测通过，真实环境边界保留，见 E-20261026-02。

- 2026-10-26：对照 Android 3.4.7-beta1 最新源码并记录功能差距；小工具改为系统 List/搜索/导航与 Form 引导，清理不可达代码和过时测试，Swift 单测上限仅计单测且固定 500；拆分 UI 大链路，更新 AGENTS.md。生成本地 1.0.4 (8) 候选，Actions 继续暂停，见 E-20261026-01。

- 2026-10-25：本地 1.0.4 (7) Release 裁剪、无覆盖率和体积优先编译，IPA 缩小 34.7%；收窄 Sentry 并清理旧校园码事件队列，补测试参数隔离保护；未触发 Actions。用户取消独立验收标识，保留正式 App 与数据；真机验收待现有标识的有效签名授权，见 E-20261025-02。

- 2026-10-25：修复 #145 内嵌 Sentry 资源框架漏签和验证遗漏；28 项脚本回归及原始产物重打包通过。遵守用户暂不触发 Actions 的约束，保留 Windows 重签/实机安装验收，见 E-20261025-01。

- 2026-10-24：经用户授权配置 Sentry CI Secret，实际验证 IPA/Archive dSYM 上传与服务端处理；同步隐私 v6 数据映射，删除过时的未采集标志和测试，见 E-20261024-01。

- 2026-10-23：为 ahutong-ios 接入经过过滤的 Sentry 诊断和隐私 v6，完成合成收件、本机回归与设备构建；新增 App Group 未授权的精确诊断和团队信息 unknown 状态，见 E-20261023-02。自动符号上传仍待令牌授权。

- 2026-10-23：按用户要求将本轮修复提交 `0aaa23b` 向 develop 集成；从 main `9e8478a` 建立此前不存在的 develop，并为其推送与 PR 启用既有完整 CI。版本号和 AIO gitlink 不变，合并前核验远端检查结果。
- 2026-10-23：修复 Widget 范围周次遗漏和缓存同步时序，隔离测试快照；固定课表顶部周选择/操作，补小工具系统返回菜单标题，增强校园码续期后的有界回退。详见 E-20261023-01；保留 Sideloadly / iOS 27 实机验收边界。

- 2026-10-22：App 与 Widget 同步提升为 1.0.4（6），交付本轮原生校园邮箱、校园码恢复、Widget 共享目录恢复、主题与课表展示、工具/设置根页修复；功能验证见 E-20261022-01/02。按维护 PR 合并并使用现有 Actions 打包 IPA，不执行商店发布或修改 AIO gitlink。
- 2026-10-20：App/Widget 同步提升为 1.0.3（5），精简 README 下载使用说明，新增 main 最小保护规则并记录实测 CI 耗时，见 E-20261020-03。
- 2026-10-20：修复岛卡提前数小时出现与圆角裁切；仅在课前 10 分钟内创建，标题/地点/倒计时增加安全留白；电话本改用系统列表、搜索、分类和拨号确认，支持大字体。证据见 E-20261020-02。
- 2026-10-20：修复待重签 IPA 缺少 App Group 声明，增加唯一共同组适配与可分享安装检查；1.0.2（4）候选及测试见 E-20261020-01，最终 Windows Sideloadly / iOS 27 授权保留真机边界。
- 2026-10-19：合并打包前修正校园码展开和滚动头像 UI 测试的瞬时几何/可点击竞态，保留尺寸和全部业务断言；Release 设备构建与 App/Widget 包结构检查通过，见 E-20261019-12。
- 2026-10-19：课表三个顶部按钮合为共享系统玻璃胶囊；课程详情移除异常撑高，按内容自适应高度，完整显示长周次、地点与教师并支持无障碍大字体滚动，见 E-20261019-11。
- 2026-10-19：课表与小工具顶部四个动作使用原生材质圆形按钮，iOS 26+ 系统 Liquid Glass、iOS 17–25 系统 Material；核对空昵称贡献者为 22级，验证记录见 E-20261019-10。
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

| 2026-10-20 | SYS-007 / REL-004 | 1.0.2（4）保留重签所需 App Group 声明、唯一共同组适配、具体失败提示与可分享安装摘要；CI 强制验证权限声明 | 20 Swift + 16 Python + 1 UI 通过，Release iphoneos 与最终 IPA 检查通过；Sideloadly 实机授权仍待复验，见 E-20261020-01 | 本次提交 |

| 2026-10-20 | OPS-008 | CI 一次构建、五组复用，全量通过；含排队用时 29:22 → 23:58（−18.4%），保留隔离、断言与证据；补齐 Mac 安装说明 | CI `39428134231`：509 Swift / 40 UI / 25 Rust / 22 Python，UI 无复验；详见 E-20261020-04 | PR #9，验证 commit `31a3809` |

| 2026-10-22 | AUTH / CARD / SYS / MAIL-NEW-03 / APP / SCH | 修复唤起续期时序和失败恢复、Widget 临时共享目录恢复；极光蓝默认与鸢尾紫、总览灰色和独立圆角、工具/设置根导航；对照 Android 接入原生校园邮箱与隔离网页回退，补隐私 v5 | 见 E-20261022-01，保持真实邮箱和 Sideloadly / iOS 27 待验边界 | 本次维护 |
| 2026-10-22 | MAIL-NEW-03 / SCH-02 / OPS-01 | 修复真实邮箱 WebVPN fragment 误拒；总览浅灰；默认关闭的周日开始周视图与学期末周日保留；隔离测试宿主及 UI 偏好 | 新登录和复用会话均完成真实只读列表验收；回归见 E-20261022-02 | 本次维护 |
