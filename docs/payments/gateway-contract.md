# 支付安全网关契约与 D-005 解除条件

## 当前安全边界

iOS 不复制 Android 客户端中的支付签名密钥，也不在 App、GitHub Actions、IPA、日志或剪贴板中保存该材料。正式构建使用 `SafetyBlockedPaymentGateway`：当受控服务端未配置时，页面可以展示和校验输入，但不会向校卡系统发起扣款。

`--demo-session` 只启用确定性内存订单，用于单元测试和 Android ↔ iOS UI 对照。订单号以 `MOCK-` 开头，不接触真实账号、真实支付密码或真实资金。

## 建议 HTTPS API

所有接口只允许 TLS，复用已认证会话或短期、限定受众的支付 Token；客户端不得获得上游签名密钥。

### 创建订单

`POST /v1/payments/orders`

请求头：

- `Idempotency-Key: <UUID>`：同一用户、同一功能内重复请求必须返回同一订单。
- `Content-Type: application/json`

请求体只包含：

- `feature`: `cardRecharge`、`bathroom` 或 `electricity`
- `method`: `bankCard`、`alipay` 或 `campusAccount`
- `amount`: 两位小数字符串，范围 `(0, 500]`
- `accountID`: 服务端签发或查询得到的账户标识

响应包含服务端订单号、可选第三方跳转 URL 和 `pending` 状态。服务端负责将客户端账户映射为上游参数并生成签名。

### 确认与查询

- `POST /v1/payments/orders/{orderID}/confirm`：校内账户方式在 TLS 请求体提交六位授权值；服务端不得写日志，使用后立即丢弃。
- `GET /v1/payments/orders/{orderID}`：返回 `pending`、`confirmed`、`rejected` 或 `unknown`。
- `POST /v1/payments/orders/{orderID}/cancel`：尽力取消；取消响应不能代替上游最终状态查询。

客户端只有收到本服务端的 `confirmed` 才显示成功。超时、App 被杀、支付宝回跳和未知响应均保留不含密码的订单号，并通过查询接口核验，禁止重复扣款。

## 日志与数据最小化

- 允许记录：匿名关联 ID、功能类型、状态码、耗时、服务端订单号的不可逆摘要。
- 禁止记录：姓名、学号、手机号、Cookie、Token、Authorization、支付密码、上游签名、完整请求/响应体。
- 订单和幂等记录需要明确保留期限、删除策略和访问审计。
- 客户端隐私清单与最终 App Store Connect 隐私标签必须按实际服务端数据用途复核。

## D-005 唯一解除条件

以下条件全部满足后，PAY-01、PAY-02、PAY-03 才能从“待验证/阻塞”变为“已完成”：

1. Android 已暴露的支付材料由负责人完成轮换，旧材料失效。
2. 提供受控 HTTPS 网关的基础 URL、认证方式和上述接口契约，签名只在服务端执行。
3. 提供不涉及真实资金的沙箱，或书面授权的小额测试账号与测试窗口。
4. 三类支付分别验证成功、拒绝、超时、取消、重复提交和 App 重启后的订单恢复。
5. macOS CI、Release Archive 敏感材料扫描、iPhone 13 Pro 回跳/重签安装回归和双端 UI 证据全部通过。

