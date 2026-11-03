# AHUTong iOS 协作规范

## 工作区与提交

- 本任务按用户要求直接在 AIO 主工作区的 `iOS/` 子仓开发，作为根仓 worktree 规则的例外；不自行迁回其他工作区。
- 修改前检查状态并保留已有改动。遵循 Gitflow：功能从 `develop` 建 `feature/*`，合入 `develop`；`main` 仅用于明确的 release/hotfix。提交使用 Conventional Commits。
- 不提交生成的 Xcode 工程、构建产物、本地配置、签名材料或密钥。推送、Actions 和合并遵守用户当前授权；不自行创建开发者标识、App Group 或修改生产 Bundle ID。

## 实现

- 支持 iOS 17+、Swift 6；`project.yml` 是工程配置来源，使用 XcodeGen 生成工程。
- 优先使用系统框架和原生 SwiftUI 导航、控件与弹层；iOS 26+ Liquid Glass 交给系统。保留现有页面布局，支持深浅色、Dynamic Type、VoiceOver 和减弱动态效果。
- 保持代码简洁、数据流明确；删除死代码，不堆叠备用路径、静默错误或无意义防御。加载、空数据、错误和登录失效须有明确反馈。
- 密码、Token、Cookie 仅使用 Keychain 持久化；临时网络/服务故障不得清除凭据。校园验证码继续使用 `RemoteCampusCaptchaRecognizer`，不自行替换 OCR。
- 相机、二维码、背景照片和业务敏感信息不进入日志或自动诊断。Sentry 依赖当前隐私同意；网络反馈默认不选，逐次预览确认，换号后旧快照失效。
- 写操作不自动重放；自动测试禁止真实支付和生产贡献。必吃榜设备包须注入并核验贡献配置，客户端内置密钥不能当作保密的服务端凭据。

## 验证与文档

- 按改动风险运行构建、单元/契约测试及必要 UI 回归；测试独立且有效，不保留冗余或过期用例，不合并场景规避预算。
- Swift 单元测试方法上限 600，使用 `python3 scripts/check-swift-test-budget.py` 检查；UI、Rust、Python 不计入。
- 本机模拟器只使用 iPhone 17 Pro，默认关闭减弱动态效果。测试使用隔离数据；覆盖安装保留已有数据和 Keychain，不卸载、清空或代替用户接受协议。模拟器结果不代表相机、Siri 或签名权限已获真机验收。
- 提交前运行 `git diff --check`，检查无关文件和敏感信息；App/Widget 版本与打包元数据须匹配。
- 文档只保留必要、当前有效的使用/构建/维护说明并原地更新。不新增迁移路线图、Android 差距对比、问卷、阶段审计或聊天过程记录；临时验证产物放在被忽略的 `build/`。
