# iOS WebView 登录与 Session 恢复设计

## 用户同意边界

登录前必须对隐私政策做出明确选择。同意后，学号、密码和校园 Cookie 使用 ThisDeviceOnly Keychain 保存，仅用于安徽大学官方页面登录与前台会话续期。拒绝或撤回同意会删除凭据与 Cookie，切换到只含课表和设置的“安大通体验用户”。

体验账户的课表来自撤回前复制的当前/下学期缓存，或用户导入的版本化 JSON。体验模式不请求校园 API。

## 首次登录

1. 以非持久化 `WKWebView` 打开 `https://jw.ahu.edu.cn/student/sso/login`。
2. 导航仅允许 HTTPS 的 `one.ahu.edu.cn` 和 `jw.ahu.edu.cn`，仅保留账号密码登录。
3. 只在受信任的 CAS 页面中捕获用户主动提交的 `#un` 与 `#pd`；未成功跳转到 `/student/home` 前不写入 Keychain。
4. 成功后导出 `WKHTTPCookieStore` 中受信任的 Secure Cookie，合并后写入 `CampusSessionSnapshot`，并初始化 Rust 内存 Cookie。
5. 以不触发重新登录的原始校验请求确认会话；失败则不持久化凭据。

## 前台无感续期

```text
校方响应被识别为认证过期
  → CampusSessionScope 分流
  → SessionRefreshCoordinator 按 scope single-flight
  → Keychain 读取凭据
  → 前台隐藏非持久化 WKWebView
  → callAsyncJavaScript 以参数填充账号密码
  → 校方页面自身脚本提交
  → 导出/合并 Cookie 并替换 Keychain 快照
  → 原安全只读请求最多重试一次
```

- App 必须位于 `.active`；系统后台不创建 WebView。
- 单次隐藏续期上限 30 秒，不循环重试。
- 明确密码错误才删除凭据；断网、5xx、DOM 变化、设备验证或超时都保留凭据，并降级为可见登录。
- 密码通过 `callAsyncJavaScript(arguments:)` 传递，不拼接到脚本、URL、日志或诊断中。

> 隐私政策已明确：首次 ADWMH 图形验证码由用户手动填写；持续同意后，后续会话恢复可将当次验证码图片发送到安大通配置的远程识别接口。请求不得附带学号、密码、Cookie、Token 或业务数据，App 不落盘或记录验证码图片/结果。当前代码仍保持首次及后续 ADWMH 验证码手动输入；远程自动识别需要在识别接口的域名/TLS、数据保留规则和学校授权确认后才能启用。

## 认证 scope 与重试

| Scope / 请求 | 恢复方式 | 原请求重试 |
| --- | --- | --- |
| 教务 GET/HEAD/明确只读 POST | 前台隐藏 CAS WebView | 最多 1 次 |
| 首页被动校园卡余额检查 | 静默失败并显示缓存/占位，不弹登录页 | 0 次 |
| 用户主动打开付款码、刷新或进入 `adwmh` 服务 | 可见官方 WebView，预填账密，用户手动完成首次验证码 | 成功后最多 1 次 |
| 支付建单、安全键盘、最终提交 | 只为后续人工操作恢复会话 | 0 次 |
| 结果未知的写请求 | 不自动重放 | 0 次 |

Apple target 不编译 Rust `/login` 路由、ADWMH 验证码 OCR 和外部 OCR 端点；Android/JNI 保持现有行为。

## 验证与安全

- 单元测试覆盖域名白名单、成功 URL、Cookie 过滤/合并、隐私决策、体验账户、JSON 课表导入和 scope single-flight。
- UI 测试覆盖拒绝隐私后只出现课表/设置两个 Tab。
- CI 阻断真实校园与支付域名；Demo 不启动生产 WebView 登录。
- 校园卡面板自动加载必须使用静默会话策略；取消或失败后，SwiftUI `.task` 重启不得再次弹出 WebView，只有新的用户操作可强制重试。
- Release Archive 会扫描 iOS 二进制，拒绝包含旧外部 OCR 端点。
- 物理 iPhone 需验证首次登录、Cookie 过期、明确错误密码、ADWMH 验证码、撤回同意和体验课表。验收记录不得包含账号、密码、Token 或 Cookie。
