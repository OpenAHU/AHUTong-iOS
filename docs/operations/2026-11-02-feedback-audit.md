# iOS 反馈提交链路审计

审计基线为已合入develop的PR #13（134377c），复核当前快捷指令/扫码分支。范围是App源码、Sentry配置及真实SDK的本地封包拦截；不提交生产反馈、不读取用户账号/Keychain、不创建新的Sentry令牌。

## 提交方式与目的地

| 入口 | 实际动作 | 目的地 |
| --- | --- | --- |
| 设置 → 意见反馈 → 问题反馈 → 预览 → 发送 | DiagnosticFeedbackPreview固定本次选择及描述，AppDiagnostics.submitFeedback通过SentrySDK.capture提交type=feedback事件和当前附件 | ratatoskr组织的ahutong-ios项目，项目ID4512304910106704；SDK按DSN向HTTPS的o4512304893788160.ingest.de.sentry.io发送envelope |
| 日志导出 → 生成加密日志 → 分享日志 | AES-256-GCM加密正文、RSA-3072-OAEP-SHA256包装临时密钥，生成AHUTONG-LOG-1格式的.ahulog文件；ShareLink打开系统分享面板 | 先保存在本机临时目录，随后由用户选择接收App/维护者；不自动上传Sentry |
| QQ反馈群 | 打开已配置的QQ群链接 | QQ；不会自动附加日志或问题描述 |

直接反馈不创建GitHub Issue，不调用OpenAHU反馈接口，不使用GitHub或Sentry管理令牌。App使用公开DSN进行客户端收件。Sentry中从该项目的User Feedback/Feedback页面查看反馈；关联错误ID仅在本次选择错误记录时附带。

## 数据边界与结论

- 诊断须在当前隐私版本同意后启用；发送时检查诊断启用状态和日志代次，账号切换、退出或撤回后旧预览不可继续发送。演示/自动化模式禁止生产发送。
- 描述最多4096字符。运行/错误记录默认勾选，网络详情默认关闭；预览固定快照，后来的请求不混入这次附件。SDK提交使用独立空Scope和当前Hint，避免全局breadcrumbs或附件重新混入。
- 自动日志排除密码、服务写入密钥、校园码、相机画面、支付及邮箱正文；运行摘要去除账号和查询参数。**主动选择的网络详情会保留部分学号、Cookie、Token及查询结果**，不是完全匿名的数据包；界面已明确提示。用户自己填写的自由文本也可能包含个人信息，不能承诺自动清除所有个人信息。
- 网络详情在提交前仅放入有界进程内存：最多5MiB、保留10分钟；正文超过256KiB不记录，HTML/二进制不采集。主动发送后由Sentry SDK处理队列、缓存和重试，不能再将它描述为“始终只在内存”。
- **直接发送的Sentry附件不使用.ahulog的公钥加密**，它依赖HTTPS传输及Sentry项目访问控制，Sentry可处理反馈正文。只有日志导出使用维护者公钥；App不包含私钥。导出路径仅写密文，并在下次导出时清理超过24小时的临时密文。
- 当前UI显示“反馈已交给发送队列”，没有把SDK接受事件当作后端已收到。此轮不证明真实生产收件或交付时效，也没有修改线上事件/告警配置。

复核代码：AHUTong/Features/Settings/FeedbackView.swift、Core/Operations/DiagnosticFeedback.swift、AppDiagnostics.swift、DiagnosticLog.swift；DSN来自project.yml，经Info.plist注入。

## 验证

SentryEnvelopeTests使用example.invalid与本地URLProtocol拦截实际SDK的envelope，验证反馈描述、仅所选附件、未选全局内容排除和DSN目标路径；没有向Sentry服务端发送测试。DiagnosticLogTests验证快照、撤回/换号失效、脱敏、内存边界及加密导出真实解密。UI复核默认关闭网络详情、必须预览和演示模式不能发送。

相关说明：[Sentry User Feedback](https://docs.sentry.io/product/user-feedback/)。本审计不将App不上传账号等同于Sentry服务端不存在IP等派生元数据。
