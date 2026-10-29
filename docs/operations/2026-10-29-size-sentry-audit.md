# 2026-10-29 包体与诊断审计

本轮只审计体积与 Sentry 配置，不替换 SDK、不改变诊断范围。用户明确选择暂不查询实际事件，因此没有创建令牌、访问项目事件或统计线上数量。唯一产品修改是必吃榜窗口详情的原生底部弹层。

## 基线与测量

- 已交付 IPA：Actions #147，1.0.6（15），`7fc7ca1d75113cf731daa1178ae040e82624fb1b`。文件为主工作区 `iOS/build/deliverables/1.0.6-15-actions/AHUTong-1.0.6-15-resignable.ipa`。
- 本地源码：上述提交加本会话尚未提交的背景、原生导航、扫码/身份码、天气和详情弹层改动。本轮在 AIO `.worktree/ios-size-sentry-canteen/iOS` 的 `codex/ios-size-sentry-canteen` 分支带入原修改，未改主工作区、推送或触发 Actions。
- Android：只读核对 master `d9e5f7486c2354acbd2440e7e5f425c383c95bf1`，不使用旧版本的 Sentry 说明推断新配置。
- 下文 MB 均为十进制 1,000,000 bytes。IPA 压缩体积、解压文件大小与链接符号占用分别记录，不能混用。

| 已交付 IPA 内容 | 解压 bytes | ZIP 中 bytes |
| --- | ---: | ---: |
| 主程序 | 12,506,432 | 5,483,991 |
| Assets.car | 785,080 | 750,674 |
| Widget 程序 | 326,096 | 107,612 |
| Sentry 资源框架占位程序 | 51,184 | 766 |
| 全部文件 / IPA | 13,748,016 | 6,391,329（含 ZIP 结构） |

相较 #145 的 9,536,231 bytes，已交付包减少约 33.0%。Sentry 采用静态链接，真实 SDK 代码在主程序内，不能将 766 bytes 的占位程序称为 Sentry 总成本。

本轮普通设备 Release 构建成功，主程序 12,737,608 bytes，Widget 308,120 bytes，全 App 文件合计 13,930,270 bytes。将文件内容按 deflate 9 独立压缩合计 6,422,181 bytes；这是未签名、未打包的内容估算，不是新 IPA，也不能替代签名后的产物门禁。该构建没有 DEBUG 演示条件。

本次 Link Map 的保留符号合计：App 与 Swift glue 5,295,279 bytes，Rust 3,032,650 bytes，Sentry 2,902,896 bytes，链接器/系统 glue 416,725 bytes。符号统计包含零填充等链接布局，既不等于压缩贡献，也不能简单相加得到文件大小。原始本地证据位于 `build/package-audit/`。

## 还值得做的优化

1. **优先做 Sentry 精简版本的同源码对比。** 当前只需原生崩溃与三个固定业务故障分类，但仍链接完整 `Sentry-Static`。官方 [9.31.0 Package.swift](https://github.com/getsentry/sentry-cocoa/blob/9.31.0/Package.swift) 提供 `Sentry-WithoutUIKitOrAppKit`；当前 binary-only 包未暴露该产品，需要更换 package/product 并适配 UIKit 专用 Options。须验证启动/关闭、隐私过滤、离线崩溃及匹配 dSYM 后才可采用；本轮未替换，尚无精确净收益。关闭回放等运行选项不等于所有相关代码自动消失。下载的 XCFramework 压缩包含多平台内容，不能用它的大小预测 iOS IPA。
2. **低风险小收益：缩小 AppMark。** 它只用于 136 pt 开屏和 72 pt 设置图标，当前是 1024×1024；512×512 足以覆盖开屏 3× 像素。`assetutil` 显示这个 rendition 占 161,392 bytes，因此可节省的图集内容小于约 0.16 MB，实际压缩差额需重编资源测量。系统 AppIcon 的 1024 资源仍保留，不删除 iPad 支持。本轮没有更改图标。
3. **Rust 要从功能边界优化。** 现有 SDK 已使用 `opt-level=z`、LTO、单 codegen unit、abort 与 strip；App 实际调用本机 Rust HTTP server，不能直接去掉 `server`、Axum 或 TLS。可以在 SDK 独立任务中测量 Tokio 的最小 feature 集和平台专用依赖，但需完整登录/查询/续期回归。仅在 Cargo.toml 删除一个依赖不保证链接后的 IPA 更小。
4. **ZIP 压缩不是主要收益。** 对同一已交付 IPA 内容重新计算，deflate 6 / 9 分别为 6,382,593 / 6,364,669 bytes，仅相差 17,924 bytes（约 0.28%）。不值得为此增加复杂打包链路。

现有 Swift `-Osize`、whole-module、dead stripping、Release 无覆盖率、发布符号裁剪和独立 dSYM 已生效。没有把系统 SwiftUI、Charts、VisionKit 当成随 App 分发的 UI 引擎，也不建议为了体积删除可用功能或诊断符号产物。

## Android 与 iOS 的实际配置

| 项目 | Android 最新源码 | iOS 当前源码 |
| --- | --- | --- |
| SDK / 项目 | Sentry Android 8.55.0；`openahu/ahutong-android`，另有 Bugly | Sentry Apple 9.31.0 静态版；`ratatoskr/ahutong-ios` |
| 启动条件 | 主进程 Application 初始化；隔离邮箱/通知 WebView 进程提前返回。初始化处没有 iOS 式隐私同意门禁 | 当前隐私政策确认且接受后才启动；撤回后停止新采集并清理专用缓存；隔离测试不启动 |
| 崩溃和故障 | Java/Kotlin、NDK/Tombstone、ANR；已处理意外异常也上报；系统线程转储/原始 Tombstone 附件 | 过滤后的原生崩溃堆栈；Widget 共享失败、快照写入失败、会话续期失败 |
| 运行记录 | 脱敏运行/错误摘要作为 breadcrumbs；活跃进程异常可附两份各不超过 96,000 字符的日志 | 通用日志、breadcrumbs、任意 Error 文本和附件链路均未启用 |
| 性能 | Release trace 采样 10%，Debug 100% | tracing、metrics、MetricKit、App Hang、Watchdog 均关闭 |
| 日活 | 每设备本地日期首次前台恢复发送 `app.dau` 根 span，独立 100% 采样；随机安装 ID，不含账号 | 未设置用户标识，自动会话与日活采集均关闭，不能算日活、留存或无崩溃用户率 |
| 主动反馈 | 用户描述及勾选日志；“网络详情”默认不选，选择后可包含 Cookie、Token、学号、请求/响应，仅过滤密码及密码派生字段 | 未实现向 Sentry 提交用户描述/网络详情的入口 |
| 环境 | `release` / `debug` | `production` / `development`；显式收件测试为 `integration-test` |

Android 的最近十分钟、最多 5 MiB 诊断缓冲在进程内存常开，单条网络正文最多 256 KiB。网络详情不进入自动运行日志附件或上述自定义 breadcrumbs；用户主动勾选后提交的附件是另一条范围更宽的链路。手动导出的 `.ahulog` 有应用层加密，而 `SentryFeedbackTransport` 上传的是 `text/plain` 附件，不能称两者都已经过该导出加密。`AppErrorHandler.beforeSend` 对缓存/ANR/Tombstone 事件提前返回，自动附件/脱敏逻辑不能据此保证所有 SDK 字段和原始系统附件均不含敏感内容。

iOS 的过滤器清空 user/request/error/extra/breadcrumbs、异常原因、栈变量、寄存器、线程名和绝对文件路径，只保留定位代码所需的堆栈地址/镜像信息，OS 与设备型号，以及有限枚举标签和数字网络错误码。每次进程内相同业务故障去重，最多 20 条；它统计的是故障出现，不等于影响用户数。校园码最终加载失败已移除，扫码内容、背景照片、课程、邮件、Cookie 和凭据均不在上报范围。

源码依据：Android [初始化与 DAU](https://github.com/OpenAHU/AHUTong-Android/blob/d9e5f7486c2354acbd2440e7e5f425c383c95bf1/app/src/main/java/com/ahu/ahutong/AHUApplication.java)、[错误处理](https://github.com/OpenAHU/AHUTong-Android/blob/d9e5f7486c2354acbd2440e7e5f425c383c95bf1/app/src/main/java/com/ahu/ahutong/error/AppErrorHandler.kt)、[反馈传输](https://github.com/OpenAHU/AHUTong-Android/blob/d9e5f7486c2354acbd2440e7e5f425c383c95bf1/app/src/main/java/com/ahu/ahutong/feedback/FeedbackTransport.kt)、[运维说明](https://github.com/OpenAHU/AHUTong-Android/blob/d9e5f7486c2354acbd2440e7e5f425c383c95bf1/docs/sentry.md)；iOS `Core/Operations/AppDiagnostics.swift` 与本目录 `sentry.md`。

## 用途与查看位置

- iOS：定位哪个版本/机型崩溃、何处执行失败、App Group 授权失败分类、教务/校园卡续期失败分类。需要同一构建的 dSYM 才能还原代码位置。故障分类有用，但当前隐私范围主动舍弃了操作轨迹、业务正文和活跃用户分母，不能据此定位所有业务错误或做增长统计。
- Android：除稳定性外还可检查抽样性能、按安装去重的日活、用户反馈与附件。安装 ID 不是学号，也不是人数；同一人多个安装分别计数，网络/配额/服务端采样仍可能漏收。
- 打开 [iOS Issues](https://ratatoskr.sentry.io/issues/?query=&statsPeriod=14d)，选择 `ahutong-ios` / `production`；Android 在 [openahu Issues](https://openahu.sentry.io/issues/?query=&statsPeriod=14d) 选择 `ahutong-android` / `release`。Android 日活在 Explore → Spans 过滤 `span.op:app.dau environment:release`，按天看 `count_unique(dau_id)`；反馈在 User Feedback。
- **本轮未查询实际事件。** 历史已验证 iOS 在 2026-10-23 收到合成事件 [AHUTONG-IOS-1](https://ratatoskr.sentry.io/issues/155737038/)，其环境为 integration-test；这不能证明当前生产事件数量。Android 文档记录过 Cookie 并发异常、Keystore 启动等待及 RenderThread/ANR 调查，也不能当作今天的未解决问题清单。

## 必吃榜详情

确认原实现从榜单、人气推荐和“吃什么”结果都使用 NavigationLink 整页跳转。本轮统一改为 item 驱动的系统 sheet，保留原有字段、筛选和抽取结果。普通字号提供 medium / large，辅助功能大字号使用 large；提供系统拖动条和完成按钮。Form 移除默认底色，详情行透明，不指定自定义 presentationBackground。

iOS 26+ 的半屏液态玻璃与全屏逐渐变为不透明由系统处理；iOS 17 沿用系统 sheet，不伪造玻璃。依据：[Apple WWDC25：Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)。测试与预览证据见迁移路线图 E-20261029-04。
