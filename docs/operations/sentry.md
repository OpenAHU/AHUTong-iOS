# iOS Sentry 诊断

项目为 [ratatoskr / ahutong-ios](https://ratatoskr.sentry.io/settings/projects/ahutong-ios/)。用户指定名称为 AHUTong-iOS，Sentry 自动将项目 slug 规范为小写。SDK 固定为官方 `sentry-apple-binaries` 9.31.0，由 `project.yml` 管理，不手工改生成的 Xcode 工程。

## 数据边界

- 只有当前第 6 版隐私政策已确认且同意，才启动 SDK。旧版同意不沿用，撤回时停止新采集并删除 App 专用的诊断缓存；正常 XCTest / UI fixture 不启动上报。
- 采集经过过滤的原生崩溃堆栈及版本、系统和设备型号；手动业务事件只接受固定的 signal / stage / failure / scope 枚举、Widget 故障分类和数字网络错误码。同一次进程内去重，最多 20 个业务故障事件。
- 不传原始 Error / NSError.userInfo、请求、Cookie、凭据、课程、邮件或付款码；清除用户信息、任意额外字段、设备名称、内存寄存器、栈变量和异常原因文本。保留可用于 dSYM 匹配的镜像 UUID 与代码地址。
- 自动网络内容、网络失败采集、通用日志、Breadcrumb、Session Replay、截图、视图层级、性能追踪和指标均关闭。项目服务端开启默认数据清洗、敏感字段清洗及禁止新事件存储 IP。
- 接收节点为 `ingest.de.sentry.io`；隐私政策与 App 隐私清单同步说明诊断用途。App 的 DSN 是公开的客户端投递标识，不是管理令牌。

## 故障入口

| signal | 含义 |
| --- | --- |
| `widget-sharing-unavailable` | 启动后无法解析共享容器，包括主 App 未授权 App Group、描述文件不可读、共享组不同及系统拒绝访问 |
| `widget-write-failed` | 共享容器可用但快照文件写入失败；缺少共享权限归入上一类，避免重复事件 |
| `session-refresh-failed` | single-flight 续期失败；区分教务与校园卡范围，不传账号 |
| `campus-code-failed` | 续期或所有有界读取最终失败；成功的备用通道不会为中途失败制造告警 |
| `installation-verification` | 显式开启的本地合成收件测试；普通测试和 CI 默认跳过 |

## Actions 与符号文件

`ios-unsigned-ipa.yml` 保存与本次 IPA 同构建的 App / Widget dSYM；`ios-release-readiness.yml` 保留 Archive 中的 dSYM。两条工作流通过 `scripts/upload-sentry-symbols.sh` 上传本次生成的 `.dSYM`，不上传源文件，不把令牌放进命令参数、App 或源码。

自动上传需仓库 Actions Secret `SENTRY_AUTH_TOKEN`。组织为 `ratatoskr`，项目为 `ahutong-ios`。Sentry 的组织令牌使用固定的 `org:ci` 权限，创建与写入 Secret 需用户确认；未配置时明确警告并保留符号产物供手动上传，不谎报已完成符号化。此令牌用于构建操作，不用于读取用户事件。

本地显式测试通过临时 `.xctestrun` 将 `AHUTONG_SENTRY_SMOKE=1` 仅传给 `AppDiagnosticsTests/testOptInSentryDelivery`；发送固定的合成事件后关闭 SDK 并删除测试缓存，不启用真实校园账号的诊断或接受其隐私政策。

2026-10-23：在 iPhone 17 Pro / iOS 26.5 上，事件 `3161569339c145ed86d6a19fe133f81a` 已在 [AHUTONG-IOS-1](https://ratatoskr.sentry.io/issues/155737038/) 收到，环境为 `integration-test`，用户数为 0。自动符号上传的授权尚待用户确认；这条 Debug 事件也尚未上传对应 Debug dSYM，不能将收件成功当成符号化完成。

参考：[Sentry 数据采集边界](https://docs.sentry.io/platforms/apple/guides/ios/data-management/data-collected/)、[上传调试符号](https://docs.sentry.io/platforms/apple/guides/ios/dsym/)。
