# Sentry 诊断

项目：[ratatoskr / ahutong-ios](https://ratatoskr.sentry.io/settings/projects/ahutong-ios/)。SDK 与版本由 `project.yml` 管理，使用 `Sentry-Static`。

## 采集与反馈

- 接受当前隐私政策后启动诊断；撤回时停止采集并清理诊断缓存。
- 采集原生崩溃、MetricKit、Watchdog、受控错误、抽样页面/请求性能和安装日活。Release 性能采样 10%；日活使用随机安装 ID，按设备本地日期去重，不使用学号。
- 自动事件去除用户资料、请求正文、错误原文、任意额外字段和栈变量。无截图、Session Replay、相机画面、背景照片或校园码最终加载失败上报。
- 运行/错误及可选网络详情在有界内存保留 10 分钟、合计最多 5MiB。网络详情默认不选，可能含学号、Cookie、Token 和查询结果；密码、服务写入密钥、支付/邮箱正文和二维码排除。换号或退出使旧预览失效。
- 设置 → 意见反馈 → 问题反馈：逐次预览后通过 SDK HTTPS envelope 发送到本项目。姓名/邮箱为 nil，附件仅包含本次选择；界面确认交给发送队列，不承诺即时送达。
- 日志导出使用 `AHUTONG-LOG-1` 公钥加密格式，仅密文落盘，由用户选择分享对象。直接发送的 Sentry 反馈不使用这套导出加密。

数据用途见[隐私映射](../release/privacy-data-map.md)。普通测试使用本地封包拦截；实际合成收件须显式设置 `AHUTONG_SENTRY_SMOKE=1`。

## 查看

- Issues：筛选项目、`production` 环境和 App release，区分 warning 与未处理崩溃；事件数不能直接当作受影响人数。
- Release Health：查看崩溃与会话稳定性。
- Explore → Spans：`app.dau` 按日对 `dau_id` 去重；页面/请求性能查看 UI span 与 `http.client`。
- User Feedback：查看用户主动提交的反馈。

## 构建与符号

App 使用公开 DSN；管理令牌只放 GitHub Actions Secret `SENTRY_AUTH_TOKEN`。IPA 与 Archive 工作流通过 `scripts/upload-sentry-symbols.sh` 上传同一构建的 dSYM，不上传源码。符号文件不放入 IPA，不能用其他构建的 dSYM 代替。

App、Widget 及静态 SDK 的资源框架均需正确签名。签名完整性和 App Group 授权分别验证，见[安装说明](../release/readiness.md)。
