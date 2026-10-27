# iOS Sentry 诊断

项目为 [ratatoskr / ahutong-ios](https://ratatoskr.sentry.io/settings/projects/ahutong-ios/)。用户指定名称为 AHUTong-iOS，Sentry 自动将项目 slug 规范为小写。SDK 固定为官方 `sentry-apple-binaries` 9.31.0，由 `project.yml` 管理，不手工改生成的 Xcode 工程。

App 使用 `Sentry-Static`：SDK 代码静态链接到主程序，包内 `Sentry.framework` 保留资源/隐私清单及 Xcode 生成的占位二进制。该资源框架也需要先完整签署再签主 App；2026-10-25 已在本地修正 #145 漏签内嵌框架的问题，并补逐个签名检查。安装完整性与 App Group 授权是两个独立检查项，修复资源签名不会授予共享权限；证据和真机边界见迁移路线图 E-20261025-01。

## 数据边界

- 只有当前第 6 版隐私政策已确认且同意，才启动 SDK。旧版同意不沿用，撤回时停止新采集并删除 App 专用的诊断缓存；正常 XCTest / UI fixture 不启动上报。
- 采集经过过滤的原生崩溃堆栈及版本、系统和设备型号；手动业务事件只接受固定的 signal / stage / failure / scope 枚举、Widget 故障分类和数字网络错误码。同一次进程内去重，最多 20 个业务故障事件。
- 不传原始 Error / NSError.userInfo、请求、Cookie、凭据、课程、邮件或付款码；清除用户信息、任意额外字段、设备名称、内存寄存器、栈变量和异常原因文本。保留可用于 dSYM 匹配的镜像 UUID 与代码地址。
- 自动网络内容、网络失败采集、通用日志、Breadcrumb、Session Replay、截图、视图层级、性能追踪和指标均关闭。项目服务端开启默认数据清洗、敏感字段清洗及禁止新事件存储 IP。
- 自动会话统计、MetricKit、App Hang、Watchdog 与客户端统计报告也关闭，不设置用户标识；当前不能据此计算日活、留存或无崩溃用户率，错误数量不能代替日活。如需活跃统计，应单独确定用途、标识与保留规则，再更新披露和实现。
- 2026-10-25 按用户要求移除校园码最终加载失败上报；过滤器丢弃已退役的 `campus-code-failed` 及未知业务分类，升级时清除旧诊断队列并启用独立 v2 缓存，防止离线旧事件绕过新过滤器发送。二维码请求与恢复行为不受影响；会话续期本身失败仍属于会话诊断。
- 接收节点为 `ingest.de.sentry.io`；隐私政策与 App 隐私清单同步说明诊断用途。App 的 DSN 是公开的客户端投递标识，不是管理令牌。

## 故障入口

| signal | 含义 |
| --- | --- |
| `widget-sharing-unavailable` | 启动后无法解析共享容器，包括主 App 未授权 App Group、描述文件不可读、共享组不同及系统拒绝访问 |
| `widget-write-failed` | 共享容器可用但快照文件写入失败；缺少共享权限归入上一类，避免重复事件 |
| `session-refresh-failed` | single-flight 续期失败；区分教务与校园卡范围，不传账号 |
| `installation-verification` | 显式开启的本地合成收件测试；普通测试和 CI 默认跳过 |

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
