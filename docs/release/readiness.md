# iOS 发布与 Personal Team 安装清单

## CI 产物

- `iOS CI`：在 iPhone 13 Pro Simulator 上构建、运行单元/UI 测试并导出 UI 证据。
- `Build unsigned IPA`：生成不含证书和描述文件的 `AHUTong-unsigned.ipa`，供本机重新签名。
- `Release readiness archive`：生成未签名 `.xcarchive`，校验 App/Widget 的隐私清单、Bundle 结构和敏感材料扫描结果。
- 本轮支付重审的最终代码产物见 `E-20260801-02`：CI `30706286051`、未签名 IPA `30706286050`、Release Archive `30706286068` 均通过；真机扣款仍只允许人工执行。

GitHub Runner 不接收 Apple ID、密码、证书或描述文件。未签名 IPA 不能直接安装到 iPhone，也不等同于 TestFlight/App Store 产物。

## 免费 Apple ID 的 7 天签名

### Xcode / Personal Team

1. 在 macOS 下载并解压未签名 IPA，或从仓库生成 Xcode 工程：`xcodegen generate --spec project.yml`。
2. 用 Xcode 打开 `AHUTong.xcodeproj`，在 App 和 Widget 两个 target 选择自己的 Personal Team。
3. 将 App、Widget 和 App Group 的 Bundle ID 改成自己账号下唯一且相互匹配的值；不要提交这些本地签名改动。
4. 用数据线连接 iPhone 13 Pro，选择设备后运行；首次安装需在设备的“VPN 与设备管理”中信任开发者。
5. 免费 Personal Team 通常需要每 7 天重新构建/安装。到期前保留本地项目和相同 Bundle ID，以减少数据迁移影响。

### Sideloadly / AltStore

1. 下载 `AHUTong-unsigned.ipa`，只在本机工具内输入 Apple ID。
2. 由工具用 Personal Team 重新签名 App 及内嵌 Widget Extension；不要把凭据、签名后的 IPA 或描述文件上传仓库。
3. 安装后验证 App 启动、登录、通知授权、桌面 Widget、付款第三方跳转和返回后的订单核验。

## 发布前人工检查

- [ ] 使用授权校园测试账号验证登录、课表和 PAY-01～05；真实支付只由测试者在明确授权的小额环境中手动确认。
- [x] PAY-01、PAY-03、PAY-05 的客户端签名与 PAY-02 安全键盘兼容逻辑已按 Android `2c33b0b` 隔离实现；协议常量只存在于私有支付兼容层，值不得进入日志、文档、诊断或验收记录。
- [x] CI/自动测试通过应用级禁写开关、runner 域名阻断和 URLProtocol/Mock 禁止连接真实扣款接口。
- [ ] 对照 `PrivacyInfo.xcprivacy` 和 App Store Connect 隐私标签，确认实际数据用途一致。
- [ ] 检查定位、通知、Widget、Quick Look/分享、支付宝跳转与回跳、弱网和取消路径。
- [ ] 固定正式 Bundle ID、签名团队、许可证、版本号、App Icon、支持与隐私政策链接。
- [ ] 生成有签名的 Release Archive，并在 Organizer/App Store Connect 完成最终验证。
