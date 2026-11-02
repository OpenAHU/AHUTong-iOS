# iOS Sentry 诊断

2026-10-30 按用户要求对齐 Android 的诊断用途，新增性能、安装日活与主动反馈，见[1.0.7验证记录](2026-10-30-diagnostics-parity.md)。此前审计见[2026-10-29记录](2026-10-29-size-sentry-audit.md)。本轮仍不查询线上事件，历史收件记录不代表当前生产数量。

项目为 [ratatoskr / ahutong-ios](https://ratatoskr.sentry.io/settings/projects/ahutong-ios/)。用户指定名称为 AHUTong-iOS，Sentry 自动将项目 slug 规范为小写。SDK 固定为官方 `sentry-apple-binaries` 9.31.0，由 `project.yml` 管理，不手工改生成的 Xcode 工程。

App 使用 `Sentry-Static`：SDK 代码静态链接到主程序，包内 `Sentry.framework` 保留资源/隐私清单及 Xcode 生成的占位二进制。该资源框架也需要先完整签署再签主 App；2026-10-25 已在本地修正 #145 漏签内嵌框架的问题，并补逐个签名检查。安装完整性与 App Group 授权是两个独立检查项，修复资源签名不会授予共享权限；证据和真机边界见迁移路线图 E-20261025-01。

## 当前采集范围（1.0.7，隐私 v7）

- 当前隐私政策确认并接受后启用；旧 v6 同意不自动扩大范围。拒绝/撤回时关闭新采集、清空有界内存日志和专用待发送缓存。普通单元/UI fixture 默认不启用 SDK。
- 原生崩溃、已处理的意外错误、Widget 共享/快照故障和会话续期失败；保留系统 MetricKit 卡顿/崩溃诊断及原始系统诊断附件、Watchdog 异常退出。不开启已弃用的 App Hang 轮询上报，不采集校园码最终失败。
- App/系统版本、设备型号、固定页面/主题/有无自定义背景标签。自动错误事件清空用户、请求、任意额外字段、错误原文、栈变量和寄存器；保留堆栈与镜像地址供符号化。系统原始诊断附件是 MetricKit 的系统报告，不是 App 请求或内存转储。
- Release 性能采样10%，Debug 100%；系统页面追踪与 App 自有 URLSession 请求耗时。请求名移除查询参数，不附正文，不向业务服务器传播 Sentry trace header；支付、邮箱与校园码的专用客户端不接入正文记录。
- 每设备本地日期首次恢复前台发送 `app.dau` 根 span，独立100%采样、不绑定当前页面 scope。`dau_id` 是本地随机安装 UUID；不是学号、不用于跨 App 跟踪，同一人多个安装分别计数。网络、服务端过滤/配额仍可能漏收，客户端标记不代表服务端确认。自动会话追踪用于 Release Health。
- 运行/错误记录在内存保留最近10分钟、合计最多5MiB；自动 breadcrumbs 仅接受受控分类的脱敏摘要，每条最多2000字符。活跃进程显式异常可附运行/错误快照，各最多96000字符；不把本次启动日志附给上次崩溃或 MetricKit 历史事件。
- 网络详情只在进程内存保存，单份正文上限256KiB，过大、二进制及 HTML 正文直接省略，避免截断敏感字段。支持 App 自有 data 请求及本地 Rust HTTP 服务的请求/响应，不宣称采集 WebKit、Rust 内部全部网络或逐行日志。切换账号、退出/重登时清空记录并拒绝旧请求追加。
- 设置 → 意见反馈包含问题反馈、日志导出、QQ 群。运行/错误默认选择，网络详情默认不选；后者可能含学号、Cookie、Token、业务查询结果，密码、服务写入密钥、支付/邮箱正文和校园码仍排除。每次提交固定预览时的快照；用户描述最多4096字符，预览最多32000字符且明确标注截断。演示模式禁止发送。界面只确认交给队列，不声称服务端已接收。
- Sentry 9.31 的便捷反馈 API 会合并全局 scope 且跳过 beforeSend；本 App 使用其公开反馈序列化模型和带独立空 scope 的事件提交，附件只放当前 Hint。离线真实 SDK 封包测试验证未选择的 breadcrumbs/附件不混入。与当前账号最近错误的关联只在选择错误记录时携带。
- 导出沿用 Android 的 `AHUTONG-LOG-1`：AES-256-GCM 正文，RSA-3072-OAEP-SHA256 包装密钥，元数据作为AAD认证。公钥来自固定 Android 源码；App不包含私钥。仅密文落盘，分享由用户主动操作，后续清理超过24小时的临时密文。Sentry反馈附件本身不使用这套导出加密，不混淆两条路径。
- 不采集截图、视图层级、Session Replay、相机画面、背景照片或传感器原始数据；不接入广告或 Bugly。自动诊断与用户主动选择的网络附件分开披露；安装标识/性能/交互更新到隐私清单。

## 查看与验证

- Issues：`ahutong-ios` / `production`；Release Health：相应版本；Explore → Spans：`span.op:app.dau environment:production`，按天 `count_unique(dau_id)`；页面/请求性能查看 `http.client` 和系统UI span；反馈在 User Feedback。
- 2026-10-29 用户选择暂不查询线上事件，本轮没有新建读取令牌，也没有读取实际问题或日活数量。合成收件仍只在显式 `AHUTONG_SENTRY_SMOKE=1` 下运行。
- 精简 SDK 实验见[1.0.7验证记录](2026-10-30-diagnostics-parity.md)。同源码压缩内容仅减少225581 bytes，且无UIKit版本编译排除Watchdog和UIViewController追踪；正式包保留9.31.0完整静态版。

## Actions 与符号文件

`ios-unsigned-ipa.yml` 从 Release Archive 打包 IPA，并保存同一 Archive 的 App / Widget dSYM；`ios-release-readiness.yml` 保留 Archive 中的 dSYM。Release 关闭覆盖率并执行发布裁剪，调试符号独立保存，不放入 IPA。两条工作流通过 `scripts/upload-sentry-symbols.sh` 上传本次生成的 `.dSYM`，不上传源文件，不把令牌放进命令参数、App 或源码。2026-10-25 的修改仅在本地验证，按用户要求未触发新的 Actions；本地 build 7、8 的新 dSYM 尚未上传。

仓库已配置 Actions Secret `SENTRY_AUTH_TOKEN`，组织为 `ratatoskr`，项目为 `ahutong-ios`。2026-10-24 经用户明确授权，创建 `AHUTong-iOS GitHub Actions` 组织令牌并保存到该仓库；权限为 Sentry 固定的 `org:ci`。令牌只用于构建操作，不用于读取用户事件，不进入源码或 IPA。未配置 Secret 的其他仓库仍明确警告并保留符号产物供手动上传。

本地显式测试通过临时 `.xctestrun` 将 `AHUTONG_SENTRY_SMOKE=1` 仅传给 `AppDiagnosticsTests/testOptInSentryDelivery`；发送固定的合成事件后关闭 SDK 并删除测试缓存，不启用真实校园账号的诊断或接受其隐私政策。

2026-10-23：在 iPhone 17 Pro / iOS 26.5 上，事件 `3161569339c145ed86d6a19fe133f81a` 已在 [AHUTONG-IOS-1](https://ratatoskr.sentry.io/issues/155737038/) 收到，环境为 `integration-test`，用户数为 0。这条历史 Debug 事件尚未上传对应 Debug dSYM，不能将收件成功当成该事件的符号化完成。

2026-10-24：[IPA #144](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39972435501/attempts/2) 和 [Archive](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39972435437/attempts/2) 均实际上传两份 dSYM，`--wait` 返回 `File processing complete` 与两个 `OK`；[项目 Debug Files 页面](https://ratatoskr.sentry.io/settings/projects/ahutong-ios/debug-symbols/) 已确认四份符号均包含 `symtab`、`debug` 和 `unwind`。IPA 的 App / Widget Debug ID 为 `bd51da6b-9870-3854-93b3-cb2c22521c69` / `b6acaaaa-0a3c-3547-8028-083e48194663`，Archive 为 `8c0ea3a4-2e60-31e8-b5c8-57952eb37486` / `021f6b57-e5a7-35c3-bead-6b32ace5f009`。两种构建的符号分别匹配各自产物，不互相替代；后续构建会自动上传本次符号。

参考：[Sentry 数据采集边界](https://docs.sentry.io/platforms/apple/guides/ios/data-management/data-collected/)、[上传调试符号](https://docs.sentry.io/platforms/apple/guides/ios/dsym/)。

2026-10-26 最终本地候选 1.0.4 (9)：App Debug ID `6871A949-B55E-35C5-B390-376D9242DCB2`，Widget `6DFCDA48-F841-3467-96DE-645C37182F02`；二进制与 dSYM 已逐一匹配，存放于 `build/deliverables/1.0.4-9-campus-services-final/`。本轮保持 Actions 暂停，未上传此候选符号；不将历史 Release 符号用于该 App UUID。

2026-10-27 此前本地候选 1.0.4 (10)：App Debug ID `CE895003-E7B0-34DC-AB00-F2E78DB82723`，Widget `6DFCDA48-F841-3467-96DE-645C37182F02`；已与该 Archive 的 dSYM 匹配，文件在 `build/deliverables/1.0.4-10-native-tools/`。包含最终分类 UI，OCR 保持服务器实现，诊断采集策略不变。

2026-10-27 最新真机安装版本 **1.0.5 (11)**：App Debug ID `4792A98F-8E98-3A47-96AA-0F802FD5AD11`，Widget `6DFCDA48-F841-3467-96DE-645C37182F02`；二进制与 dSYM 逐一匹配，存放于 `build/deliverables/1.0.5-11-device/`。Actions 继续暂停，新符号未上传，不宣称此 App UUID 已服务端符号化；诊断采集策略不变。

2026-10-27 最新本地实机验收包 **1.0.5 (12)**：App Debug ID `9BD909DB-3235-3E91-BF45-0E596EDD612B`，Widget `80430A69-031D-3780-B988-1005B9B39258`；与 Archive 的 dSYM 逐一匹配，存放于 `build/deliverables/1.0.5-12-device/`。已覆盖安装并正常启动，用户功能验收待确认；本轮不推送、不触发Actions，符号未上传，采集策略不变。

### 2026-10-27 本地验收修正版1.0.5（13）

首页刷新/深色导航修正使用正式Release重新Archive并保留数据覆盖安装，同一生产标识与原授权。App dSYM UUID `843D39E6-C994-3350-8A94-C52FE1813E5C`，Widget仍为 `80430A69-031D-3780-B988-1005B9B39258`，均已匹配二进制并保存于 `build/deliverables/1.0.5-13-device/AHUTong-1.0.5-13-dSYMs.zip`；没有上传新符号或触发Actions。Sentry采集范围与同意策略未变。安装后的命令启动曾以0退出，未发现新主App崩溃报告；随后真实屏幕和最终主进程复核正常，详细本地记录见迁移路线图E-20261027-11。

### 2026-10-27 必吃榜配置验收包1.0.5（14）

App dSYM UUID `ACDEF577-52A0-38A1-9763-15BFC5524B5D`，Widget仍为 `80430A69-031D-3780-B988-1005B9B39258`，均与二进制匹配并保存于 `build/deliverables/1.0.5-14-device/AHUTong-1.0.5-14-dSYMs.zip`。已覆盖安装并正常启动，符号未上传，不触发Actions。IPA保留公开DSN，扫描未发现Sentry管理令牌格式或CI Secret变量名；贡献客户端密钥可提取的独立审计见迁移路线图E-20261027-13。采集与同意策略未变。

### 2026-10-28 1.0.6（15）

本地Release App UUID `CFE9D995-325B-3F2B-9468-9C26BE7867CD`、Widget UUID `80430A69-031D-3780-B988-1005B9B39258`均与本次Archive的dSYM匹配。用户已授权恢复Actions；本次云端产物由两条设备workflow自动上传各自匹配符号，运行结果见[PR #12](https://github.com/OpenAHU/AHUTong-iOS/pull/12)关联Checks。云端重新构建的UUID以实际产物为准，不沿用本地UUID。Sentry管理令牌仅用于符号上传步骤；采集范围不变，不新增校园码失败或日活采集。
