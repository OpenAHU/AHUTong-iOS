# AHUTong iOS 协作规范

## 开发与分支

1. 不直接在 `main` 上开发；每个明确目标使用独立功能分支。
2. 提交信息遵循 Conventional Commits，避免混入无关重构、格式化或本地文件。
3. 开始修改前检查工作区状态，保留其他人的未提交改动。

## 工程与代码

1. `project.yml` 是 Xcode 工程配置的唯一来源；使用 XcodeGen 生成 `AHUTong.xcodeproj`，不提交生成目录。
2. 当前临时基线为 iOS 17、Swift 6 和 SwiftUI；最终产品参数以迁移路线图中的决策为准。
3. 优先使用 SwiftUI、Swift Concurrency、`URLSession`、`Codable` 和系统框架，不为单个功能引入不必要依赖。
4. 用户界面必须覆盖加载、空数据、错误和必要的登录失效状态，并支持深浅色、Dynamic Type 与 VoiceOver。
5. 密码、Token 和 Cookie 只能进入 Keychain；禁止提交或记录账号、密钥、支付签名、证书及敏感请求内容。

## 测试与进度

1. 每个功能切片至少为关键模型、解析或状态机添加单元/契约测试，主要路径添加必要的 UI smoke test。
2. Windows 侧只能进行静态检查；“已完成”必须有 macOS/Xcode 构建或测试证据。
3. 每完成一个可验收切片，必须同步更新 `docs/migration/android-parity.md` 的摘要、功能矩阵、验证证据和变更日志。
4. 提交前运行 `git diff --check`，并确认没有构建产物、本地配置或敏感信息。
