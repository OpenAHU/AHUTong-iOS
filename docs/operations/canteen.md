# 必吃榜与自愿贡献

Android 对照基线：`90a0fdc`（master / develop，3.4.7）。接口契约来自该提交的 `docs/canteen-server-api.md`、`CanteenGateway.kt` 和 `CanteenFootprint.kt`。

## 页面与统计

- 必吃榜保留周期、校区、排名、样本数量/日期和图表，移除底部榜单说明与重复的用法文案。榜单、我的记录和吃什么共用原生食堂选择按钮，左侧系统正文色、右侧主题色；食堂可多选。校区变化后清空上一个校区的食堂选择。蕙园/梧桐园的接口别名合并展示，查询兼容有无“食堂”后缀。
- 我的记录主动读取近180天的校园卡支出，账单及分析结果仅在当前页面内存中。分页读取完整范围，任一页失败或超过60页不发布部分总额；名称映射失败不阻止查看消费记录。不使用跨账户全局缓存。
- 只计午餐 `[10:30, 14:00)` 与晚餐 `[16:30, 22:30)`；同日、同窗口、同餐段，自该餐第一笔起5分钟内的记录合并为一餐。没有终端号时按食堂及楼层区分，避免合并不同地点。个人平均每餐与公开榜单平均每笔口径不同。
- “吃什么”独立读取所选范围的公开榜单，在服务器允许的最多200个榜单窗口中，筛选已命名窗口等概率抽取；不把热度用作抽中权重，不虚构菜品。24次逐渐减速的切换约3秒，结果显示所选范围热度排名、位置、平均每笔消费。减弱动态效果时等待3秒后淡入结果，不做纵向滚动；离开页面或进入后台取消抽取。

## 贡献边界

- 不自动上传，不沿用 Android 的前后台自动上传/定时同意状态。我的记录右上角原生上传图标打开近30天贡献预览；预览页右上角图标执行上传。移除记录页底部贡献按钮和说明，数据范围/IP/撤回限制仅在预览和隐私政策说明。每次贡献都必须查看预览、单独同意并确认。
- 交易请求仅含 `terminal / ts / amountCents / canteen / floor`，不含学号、订单号、卡号、设备ID或校园会话。保留原账单 `effectdateStr` 的秒级时间；分钟格式补秒为00，不使用上传时刻。按服务器 `(terminal, ts, amountCents)` 去重。
- 只贡献最近30个自然日截至当前时刻、金额大于0且不超过500元、有终端号且满足正餐时段的食堂支出。每批400笔，失败即停止，不自动重试；部分成功明确报告已确认笔数，用户重试时由服务器去重。空集合不发送心跳请求。
- 未命名窗口可以主动补充1–20字名称，确认窗口终端号、规范食堂位置、名称和样本笔数后发送到待审队列。这里不发送原始商户全文、单餐时间或金额，不增加持久的报告者UUID。
- 网络服务仍可看到连接IP，时间/地点/金额可能反映活动规律，不能描述成“完全匿名”或“绝对无法关联”。提交后不能按个人身份撤回。说明同时出现在预览及隐私政策中；新增用途依赖本次独立同意，不借旧版总隐私同意开启自动上传。
- 公开读取和贡献使用独立的临时 URLSession，无学校 Cookie、凭据存储或缓存；写请求拒绝重定向，客户端写入密钥只附加给贡献POST。演示数据始终禁止提交。

## 构建配置

GitHub Actions Secret 名称：`CANTEEN_WRITE_KEY`，由接口维护者提供与 Android 一致的客户端写入密钥。现有 Secret 无法通过 GitHub API 读出；不要把密钥放进聊天、源码或构建日志。

配置入口：[OpenAHU/AHUTong-iOS Actions Secrets](https://github.com/OpenAHU/AHUTong-iOS/settings/secrets/actions) → New repository secret。名称填 `CANTEEN_WRITE_KEY`，值直接粘贴到 Secret 框，不使用普通 Variables，也不发送到聊天。保存 Secret 本身不会触发构建；2026-10-27 用户配置后已通过仅列名称/更新时间确认该 Secret 存在，未读取原值。

两个打包 workflow 在 Archive 前调用 `scripts/configure-canteen-key.py --require-key`，只在 Runner 临时目录生成权限0600的 xcconfig，并通过 `-xcconfig` 注入；缺失密钥或包含非法请求头字符时立即失败。Archive 后再用 `--verify-app --require-key` 核对实际 App 的配置与本次 Secret 一致，防止产生成功但不能贡献的官方 IPA。CI额外为Base64派生值注册 `add-mask`，防止Xcode输出构建环境时泄露未被原值遮蔽的编码。7项Python测试覆盖私有权限、输出遮蔽、可选开发配置、必需密钥及构建配置校验；通用日志也遮蔽 `X-Api-Key`。

未注入密钥的开发包仍可查看记录/榜单/抽取，预览中的上传按钮停用；官方设备包则必须通过上述门禁。Secret 不会更新已安装IPA，也无法从GitHub读回原值供本机打包。1.0.5（13）不含该密钥及最新按钮调整；用户通过本机隐藏输入提供密钥后，1.0.5（14）已完成注入、签名和实机覆盖安装。2026-10-28 用户明确恢复推送与 Actions 授权，当前版本提升为 **1.0.6（15）**，延续 [PR #12](https://github.com/OpenAHU/AHUTong-iOS/pull/12) 构建；云端结果及产物以该 PR 关联的 Checks 和 Actions 为准。

本机如需构建可提交的版本，先通过本地安全方式设置环境变量 `CANTEEN_WRITE_KEY`，再运行：

```sh
python3 scripts/configure-canteen-key.py build/Canteen.xcconfig.local --require-key
# 在现有 xcodebuild 命令上追加：
# -xcconfig build/Canteen.xcconfig.local
# 本地使用 -quiet，避免详细构建环境进入未遮蔽的日志。
# Archive 后，path 换成实际 .app 路径，保留同一个环境变量：
python3 scripts/configure-canteen-key.py path/to/AHUTong.app --verify-app --require-key
```

Base64 只用于避免 xcconfig 特殊字符解析，不是密钥保护方案。与 Android 的 BuildConfig 客户端密钥一样，打进 App 的写入密钥可被提取，不能作为用户身份认证或服务端防滥用的唯一手段；服务端仍负责限流、去重和审核。该密钥不是校园账号凭据。

2026-10-27 实际 IPA 审计：1.0.5（14）的 `Payload/AHUTong.app/Info.plist` 包含可离线还原的密钥编码，任何持有该 IPA 的人都可以提取；没有把原值或编码记录进审计报告。未发现 Sentry 管理令牌格式或 CI Secret 变量名，公开 Sentry DSN 保留。当前客户端只对指定贡献 POST 附加密钥，不附带学校 Cookie、拒绝重定向，但不能据此保证持有密钥的外部调用者遵守客户端约束。若接口维护者要求该密钥保密，必须停用/轮换此值并改用服务端保管或短期受限授权；改字段名、混淆和 Base64 不能解决客户端保密问题。未通过真实贡献测试服务端写入权限。

同日追加上游对照：Android master `eaf65cf7c6dc1204e889eb93408c92ef00b23c63` 的 `publish.yml` 从同名 Secret 注入环境变量，`app/build.gradle.kts:24–32,107` 将值写入 `BuildConfig.CANTEEN_WRITE_KEY`，并明确注释客户端值可提取；`CanteenApi.kt:64–74` 将其作为 `X-Api-Key` 请求头。因此两端都不是客户端保密方案。Android 接口文档将写入键与管理员 HTTP Basic 分开，并描述服务端限频；未审查实际服务端部署或提取正式 Android APK。

进一步确认master/develop同为该提交，工程标注3.4.7（304012）。Android客户端采用HTTPS、上传同意闸门、成功30分钟/失败5分钟节流、400笔分批、去标识字段以及众包报告者随机UUID；这些限制可以减少正常客户端误用，不能阻止提取密钥后直接调用接口。接口文档描述IP写入限频、POS每日配额、金额/时间校验、三字段去重和名称人工审核，均未实测服务端部署。另发现诊断路径的静态缺口：`AhuHttp`为必吃榜客户端安装`FeedbackNetworkInterceptor`，后者逐项保留请求头值，NETWORK环形缓冲仅调用`DiagnosticSanitizer.passwords`，未对`X-Api-Key`专门遮蔽；因此该客户端键会进入私有内存网络详情，用户选择提交网络详情时可能一并发送。没有验证实际反馈附件，也不将其描述为默认公开或自动上传。本轮未修改Android。

2026-10-27 审计时的线上最新 IPA 为 [#146](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/40366421271)，构建号11；同次 [Archive #89](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/40366421382) 也为1.0.5（11）。两者于北京时间2026-10-27凌晨构建，早于Secret更新时间14:35。下载并逐文件检查IPA和Archive，无贡献配置字段，也未检出本机14中该密钥的原值/编码或Sentry令牌格式；三条运行（含iOS CI）的日志扫描同样无匹配，两个符号上传步骤中的令牌环境值均为`***`。当时上游构建提交`24a7e013`的workflow尚未接入贡献Secret；本地14与CI接线未上传。审计文件保存在被忽略的`build/actions-secret-audit-20261027/`，该次检查未触发新Actions。

隐私清单新增 `NSPrivacyCollectedDataTypePurchaseHistory`，用途为 App 功能、无跟踪、不附带个人标识；字段名称采用 [Apple 隐私清单定义](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype)。这不代表服务端网络日志不包含IP。

本轮只读探测公开接口和使用本地 fixture 验证写入契约，不向生产服务提交测试记录。真实贡献的204回执、名称审核结果与服务端IP/日志保留策略需由服务维护者验收。
