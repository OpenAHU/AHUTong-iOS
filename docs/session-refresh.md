# iOS 登录 Session 过期恢复设计

## 目标与参考

本设计固定参考 Android commit `2c33b0bb923f197f1d209cb58589a6b5d052cd9f` 的 `AutoLoginInterceptor` 与 `TokenAuthenticator`：认证边界识别登录重定向，多个失败请求共享一次重新登录，登录成功后只重试原只读请求一次。

实现链路为：

```text
学校响应
  → Rust 共享认证响应检查
  → typed campus_session_expired
  → 本地 HTTP 401 + 固定错误码
  → Swift CampusCoreError.unauthorized
  → App 级 SessionRefreshCoordinator single-flight
  → 清 Rust 内存 Cookie → Keychain 凭据登录 → dump Cookie
  → 原子替换 CampusSessionSnapshot
  → 原只读请求最多重试一次
```

## 真实根因

旧实现只有课表解析器识别少量登录页 HTML，随后返回普通英文字符串。`server/error.rs` 只把精确的 `campus_login_rejected` 映射为 401，因此 Session 过期经本地服务变成 500。Swift 只对 401 刷新，`AppModel.restore()` 又把 500 作为离线错误保留已登录外观，最终表现为进入主页后所有在线功能失效。

校卡 Token 和部分 Swift 直连服务还各自清理临时 Token，却不会通过同一根 CAS Session 刷新重试当前只读请求；并发请求也没有 App 级 single-flight。

## Rust 错误契约

Rust 使用真正的 `CampusSessionExpired` 错误类型，其稳定公开码为 `campus_session_expired`。服务层通过类型 downcast 分类，不解析任意英文错误文本。

共享认证响应边界在业务 JSON/HTML 解析前检查：

- 远端明确返回 401/403；
- reqwest 跟随跳转后的最终 URL 为 CAS/JWXT 登录 URL；
- `tologin`、`refer` 等明确登录重定向；
- `text/html` 或 HTML 响应包含 `loginForm`、登入页面标题或同时具备用户名/密码的 CAS 登录表单。

课表、下学期课表、当前周、考试、成绩/多学籍/排名、校园卡余额、付款码和校卡 Token 均经过同一边界。学校 5xx、网络失败和格式变化分别保留为非认证错误，不能被映射成 401。错误、日志和本地 HTTP 响应不包含 Cookie、Ticket、Token、密码、请求体或上游响应体。

本地服务返回契约：

| 场景 | HTTP | 固定错误码 | Swift 语义 |
| --- | --- | --- | --- |
| 已登录会话过期 | 401 | `campus_session_expired` | `.unauthorized`，允许协调刷新 |
| 学号密码被登录接口明确拒绝 | 401 | `campus_login_rejected` | `.credentialsRejected`，清理失效凭据并回登录页 |
| 学校依赖暂不可用 | 503 | `campus_service_unavailable` | 保留本地身份与 Keychain |
| 其他服务/解析错误 | 500 | `campus_service_error` | 保留本地身份与 Keychain |

## Swift single-flight 与凭据边界

`SessionRefreshCoordinator` 是 App 级 actor。首个 401 创建共享 `Task`，之后同时到达的请求等待同一个结果，不再次调用登录。刷新严格按以下顺序执行：

1. 用 canonical student ID 从 ThisDeviceOnly Keychain 读取学号和密码；
2. 以空 Cookie 初始化 Rust，清理失效的内存 Cookie；
3. 执行校园登录；
4. 从 Rust dump 新 Cookie；
5. 以单次 Keychain set 替换 `CampusSessionSnapshot`；
6. 共享 Task 完成，所有等待请求继续。

密码和 Session Cookie 继续保存在 Keychain，本次修复不迁移到 GuiXu。学号保存、读取和删除统一采用“去首尾空白 + POSIX 大写”的 canonical ID；可识别的旧 Keychain account 会在读取时迁移。升级后若只有 Snapshot、没有可定位的 CredentialStore 凭据，App 清除会造成启动循环的旧 Snapshot，并在登录页显示一次明确的重新登录提示。

只有 `campus_login_rejected`，或成功重登录后的同一只读请求再次得到明确认证拒绝，才清除 Keychain 凭据。断网、超时、学校 5xx、解析变化不会退出本地身份，也不会删除凭据。

## 自动重试矩阵

| 请求类型 | 检测过期后刷新 Session | 自动重试原请求 | 上限 |
| --- | --- | --- | --- |
| GET / HEAD | 是 | 是 | 1 次 |
| 明确只读的校卡 Token POST | 是 | 是 | 1 次 |
| 校卡只读查询 POST | 是 | 是 | 1 次 |
| 支付建单、支付提交、动态键盘等写 POST | 是，为后续人工操作准备新会话 | 否 | 0 次 |
| 网络结果未知的写请求 | 否自动重放 | 否 | 保持原订单待确认 |

校卡只读客户端遇到 Token 过期时会清除内存 access token/临时 Cookie，等待相同的根 CAS Session 刷新，重新获取校卡 Token，然后只重试查询一次。CMB、网费和生产支付客户端复用同一协调器；不会各自竞争重新登录。生产支付的建单和最终提交绝不因刷新 Session 被自动重复发送。

## 测试与安全

- Rust fixture 覆盖登录 HTML、CAS/JWXT 最终 URL、登录重定向、401/403、七类受保护功能以及非认证的网络/5xx/解析失败；服务错误转换测试锁定 401 JSON 契约。
- Swift URLProtocol/Mock 覆盖并发 401 single-flight、登录 HTML/最终 URL、GET 一次重试、第二次 401 终止、5xx 保留身份、canonical Keychain、校卡 Token 更新，以及支付 POST 不重放。
- CI 设置 `AHUTONG_CI_DISABLE_LIVE_PAYMENT=1` 并阻断真实支付域；所有自动测试只使用本地 fixture、URLProtocol 或 Mock，不执行真实登录和真实支付。
- 物理 iPhone 只需人工验证真实校园会话过期后的恢复、Keychain 升级提示，以及支付前 Session 刷新不重复建单；测试记录不得包含账号、Cookie、Token 或密码。
