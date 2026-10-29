# 1.0.7：诊断对齐、SDK 对比与更新提醒

本版为 1.0.7（16）。Android 参考 `d9e5f7486c2354acbd2440e7e5f425c383c95bf1`；iOS 从 `7fc7ca1` 接续，背景、原生导航、扫码/身份码、天气和必吃榜详情已整理为 `780b71e`。按用户要求，本轮只审查 Sentry 配置与离线封包，不读取生产事件。

## SDK 实测与选择

两个候选均从同一 `780b71e` 快照、同一 Xcode 27、iphoneos Release、`-Osize`、无覆盖率及发布裁剪构建，均构建成功。没有改变图标。

| 9.31.0 候选 | App 文件合计 bytes | 各文件 deflate 6 内容合计 bytes |
| --- | ---: | ---: |
| Sentry-Static | 13,929,686 | 6,441,485 |
| Sentry-WithoutUIKitOrAppKit | 13,809,855 | 6,215,904 |

精简候选压缩内容少 225,581 bytes（约3.5%），但并非同签名 IPA 差额。主程序变小，同时新增约2.94MB的动态 SentryWithoutUIKit 框架，不能只比较主程序。

正式依赖保留完整静态版。官方无 UIKit 版本在 `SENTRY_NO_UI_FRAMEWORK` 下编译排除 Watchdog 集成，且没有 UIViewController 自动追踪。收益不足以满足“功能一致”的前提。继续保留 Swift whole-module/`-Osize`、Rust LTO/体积优化、dead stripping、Release 无覆盖率和独立 dSYM。

证据保存在被忽略的 `build/sdk-compare/`。精简 XCFramework 下载 SHA-256 为 `9d146d1e8479d47955d5de636071b7e90969659817b92b33e6e7f4da3c1b0304`。源码依据：[官方9.31产品定义](https://github.com/getsentry/sentry-cocoa/blob/9.31.0/Package.swift)、[Watchdog编译条件](https://github.com/getsentry/sentry-cocoa/blob/9.31.0/Sources/Swift/Integrations/WatchdogTerminations/SentryWatchdogTerminationTrackingIntegration.swift)。

## 与 Android 对齐的用途

| 用途 | iOS 本版 | 平台和隐私边界 |
| --- | --- | --- |
| 稳定性 | 原生崩溃、主动捕获意外错误、Widget/续期故障、Watchdog、MetricKit诊断及原始系统附件 | 使用系统机制对应 Android ANR/Tombstone；不复制 Bugly；不报告校园码最终失败 |
| 性能 | 系统页面追踪、自有 URLSession 请求耗时；Release10% | 不向学校传播 trace header，不自动采集业务正文；不是所有 WebKit/Rust 内部请求 |
| 活跃 | 随机安装ID、本地日期、独立100%采样的 `app.dau` | 安装数不是人数；离线/配额可能漏收；不是服务端确认 |
| 排错记录 | 最近10分钟、总计最多5MiB内存；运行/错误自动摘要；显式异常各最多96000字符附件 | 不把新启动日志附给历史崩溃；无截图、回放、视图树 |
| 主动反馈 | 原生表单，选择运行/错误/网络快照，预览后发送 | 网络默认不选；可含学号、Cookie、Token和查询结果；密码、写入密钥、验证码、支付/邮箱正文、校园码排除 |
| 导出 | 与 Android 公钥和 `AHUTONG-LOG-1` 格式兼容，AES256GCM + RSA3072OAEP | 仅密文落盘；App无私钥；Sentry反馈附件是另一条经用户授权的传输路径 |

隐私版本升至 v7，旧同意不会自动扩大采集范围。换号、退出、重登清空内存并使未完成请求/反馈预览失效；撤回关闭 SDK 并清理待发送缓存。完整范围与查看位置见 [sentry.md](sentry.md)。

Sentry 9.31 的反馈跳过 `beforeSend`，因此使用公开反馈序列化模型、独立空 scope 与当前 Hint 附件。离线 SDK 测试在 `.invalid` URLProtocol 中截获实际封包，验证未选择的全局 breadcrumbs/附件不会混入；另验证 DAU 在普通性能采样为0时仍生成含安装ID/日期的完整事件。没有向生产发送这些测试。

## 更新提醒

- 进入可用主界面或恢复前台时检查；同进程最多每小时一次，不后台轮询，不阻塞登录或校园码快捷跳转。
- 只查询官方 `ios-unsigned-ipa.yml` 最近5条成功运行，并确认存在名称匹配、非空、未过期的 IPA artifact。失败构建、只有符号文件和已过期下载不提示。
- Actions 包嵌入本工作流 run number；本地包嵌入构建时间。分别按运行号或创建时间排除已安装/旧构建，旧运行重跑不变成新版本。
- 自动提示时持久化最高已提示运行号。点“稍后”也不再提示该构建，下一次必须有更大的成功运行号。设置中的手动检查仍可查看可用更新。
- 本功能使用公开 GitHub API，不内置 GitHub 令牌；下载页由系统浏览器打开，GitHub artifact 下载可能要求登录。IPA仍需签名安装，不进行系统外自动安装。
- App内“更新说明”已替换为本版四条简短变化。

依据：[GitHub Workflow Runs API](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-workflow)、[Artifacts API](https://docs.github.com/en/rest/actions/artifacts#list-workflow-run-artifacts)。

## 测试与验收

Swift 单元方法预算改为600；未扩展到UI/Rust/Python。当前526项Swift、96项UI（每项恰好归属一个CI分片）。一条旧测试仍要求诊断完全不关联标识，与安装日活的新范围冲突，已改为验证“关联安装、禁止跨App跟踪”；未删除断言或跳过规避。

本机指定iPhone17Pro/iOS26.5、Release优化下的隔离测试：`build/acceptance-1.0.7.xcresult` 共528项，527通过、1项原有线上Sentry收件opt-in跳过、0失败；其中526项Swift单元、2项原生反馈/必吃榜UI。32项Python脚本检查为31通过、1项环境条件跳过；96项UI全部恰好分片一次，本地本轮没有声称全跑96项。已确认构建元数据随App打包。最终可贡献IPA由本分支Actions使用已配置的 `CANTEEN_WRITE_KEY` 构建，工作流强制核对实际App配置并独立保留dSYM、SHA-256和签名结构验证；结果以本次PR的Checks和产物为准。本机旧xcconfig为空，未将缺少贡献配置的本地Archive作为交付包。真实贡献写入、照片视差/第三方跳转及物理机使用留待用户验收。Widget共同App Group授权仍按先前决定延期，不能把SDK或打包修正当成共享授权已解决。
