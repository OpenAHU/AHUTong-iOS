# iOS 发布与设备测试安装清单

## CI 产物

- `iOS CI`：在独立 iPhone 17 Pro Simulator 上构建、运行单元/UI 测试并导出 UI 证据。
- `Build unsigned IPA`：生成不含证书和描述文件的 `AHUTong-unsigned.ipa`，供本机重新签名。
- `Release readiness archive`：生成未签名 `.xcarchive`，校验 App/Widget 的隐私清单、Bundle 结构和敏感材料扫描结果。
- 本轮支付重审的最终代码产物见 `E-20260801-02`：CI `30706286051`、未签名 IPA `30706286050`、Release Archive `30706286068` 均通过；真机扣款仍只允许人工执行。

GitHub Runner 不接收 Apple ID、密码、证书或描述文件。未签名 IPA 不能直接安装到 iPhone，也不等同于 TestFlight/App Store 产物。

## 申请制 Ad Hoc 网页安装（付费开发者团队）

2026-10-14 调研结论：安大通受限设备测试优先使用申请页、一次性 UDID 登记和 Ad Hoc OTA 安装。申请者只使用 Safari 和系统设置，不需要安装 Sideloadly、AltStore 或签名工具，也不需要开发者的 Apple Account。

### 申请者流程

1. 在 Safari 填写申请，选择需要的应用。
2. 首次使用时确认设备登记。Safari 不能直接读取 UDID；纯手机流程需要用户在系统设置中确认一个 `Profile Service` 描述文件，向申请服务回传 UDID、设备型号和系统版本。只收集必需属性，不使用 MDM、VPN 或根证书载荷；已提供 UDID 的用户可跳过此步骤。
3. 审核通过且 Apple 设备状态可用后，返回个人下载页，逐个点击“安装”。页面通过 `itms-services://?action=download-manifest&url=<HTTPS manifest URL>` 调用系统安装器。
4. 按系统提示完成首次运行设置，包括需要时启用开发者模式并重启。后续应用更新仍从同一个页面安装，通常无需再次登记设备。

这些是三个网页阶段及首次系统确认，不能承诺初次使用只有两三次点击或完全不安装任何描述文件。UDID 收集协议见 [Apple Profile Service 文档](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/iPhoneOTAConfiguration/profile-service/profile-service.html)；网页导出和 manifest 见 [Xcode OTA 分发选项](https://help.apple.com/xcode/mac/current/en.lproj/devde46df08a.html) 与 [导出应用](https://help.apple.com/xcode/mac/current/en.lproj/dev23ea8b877.html)。实际 UI 要在目标 iOS 版本上用一台新登记真机验证。

### 管理和签名

- 审核通过后才登记设备，避免不可回收的年度名额被未通过申请消耗。按 UDID 去重，同一台设备安装多个应用仍占一个该类别的设备名额。
- 后台先确认 Apple 设备已启用，再更新每个 App ID 的 Ad Hoc profile。安大通 App 与 Widget 均需签名、均需覆盖目标 UDID，并使用同一个有效 App Group。
- 所有获准设备可共享同一批签名 IPA；新增 UDID 后为新批次重新生成 profile 并签名，无需为每位申请者重编译源码。已有安装无须仅因增加另一台设备而重新安装。
- 下载页的认证与系统安装请求分开设计：manifest 和 IPA 使用有足够下载时间的 HTTPS 签名 URL，不能依赖 Safari 登录 Cookie。证书私钥、`.p12` 与 API 密钥保留在管理员签名环境，申请者只拿最终 IPA 的安装链接。
- 自动化可调用 [App Store Connect Devices API](https://developer.apple.com/documentation/appstoreconnectapi/devices) 登记和查询设备；先人工签一台设备跑通，再接入审批后的签名任务。

[Apple 设备名额](https://developer.apple.com/help/account/devices/devices-overview) 是每会员年度、每设备类别各 100 台；停用不返还名额。[设备登记处理规则](https://developer.apple.com/help/account/reference/device-registration-updates) 指出：新会员或失效超过一个月后恢复的会员，第 11～100 台可能需要 24～72 小时，处理完成前不能进入 profile。页面应显示“等待设备启用”，不能显示虚假的立即可安装。

### 有效期与第三方应用

下载页展示实际“有效至 YYYY-MM-DD”，根据 App/扩展的 profile 和证书有效期计算；不要将“一年签”承诺为每个申请者从安装日起固定 365 天。新团队的 development / Ad Hoc 应用首次运行还需要连接 Apple 的 PPQ 服务；不要为追求免联网使用仅 7 天有效的 offline profile，见 [Apple provisioning 更新说明](https://developer.apple.com/help/account/provisioning-profiles/provisioning-profile-updates)。

Kazumi 的[官方构建工作流](https://github.com/Predidit/Kazumi/blob/main/.github/workflows/release.yaml) 生成 iOS 未签名 IPA，技术上可以作为重签输入，但它与安大通的分发授权要分别确认。[Kazumi README](https://github.com/Predidit/Kazumi/blob/main/README.md) 将代码列为 GPL-3.0，同时明确图标具有单独版权；不能默认代码许可证覆盖图标的再次分发。提供二进制时需处理对应源码和版权声明。

[Apple Developer Program 协议](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/) 的 Ad Hoc 条款针对 `Your Applications` 和关联群体的有限设备分发，100 台额度本身并不构成签任意第三方应用的授权。上线面向申请者的 Kazumi 分发前，需要确认上游授权及开发者协议适用性；本项目优先推进安大通测试者申请流程。

## 免费 Apple ID 的 7 天签名

### Xcode / Personal Team

1. 在 macOS 下载并解压未签名 IPA，或从仓库生成 Xcode 工程：`xcodegen generate --spec project.yml`。
2. 用 Xcode 打开 `AHUTong.xcodeproj`，在 App 和 Widget 两个 target 选择自己的 Personal Team。
3. 将 App 和 Widget 的 Bundle ID 改成自己账号下唯一且相互匹配的值。需要共享课表时，两个 target 都须获授权使用同一 App Group，并设置 `AHUTONG_APP_GROUP`；不要提交这些本地签名改动。
4. 用数据线连接 iPhone 13 Pro，选择设备后运行；首次安装需在设备的“VPN 与设备管理”中信任开发者。
5. 免费 Personal Team 通常需要每 7 天重新构建/安装。到期前保留本地项目和相同 Bundle ID，以减少数据迁移影响。

Apple 的[能力支持取决于平台及会员类型](https://developer.apple.com/help/account/capabilities/capabilities-overview)。如果当前团队无法为双方授权 App Group，修改标识字符串本身不能解决共享课表；必须以实际 profile、签名权限和设备结果为准，不能承诺免费重签后完整支持 Widget。

### Sideloadly / AltStore

1. 下载 `AHUTong-unsigned.ipa`，只在本机工具内输入 Apple ID。
2. 由工具用 Personal Team 重新签名 App 及内嵌 Widget Extension；不要把凭据、签名后的 IPA 或描述文件上传仓库。
3. 安装后验证 App 启动、登录、通知授权、桌面 Widget、付款第三方跳转和返回后的订单核验。

## 发布前人工检查

- [ ] 使用授权校园测试账号验证登录、课表和 PAY-01～05；真实支付只由测试者在明确授权的小额环境中手动确认。
- [ ] 验证隐私 v4 接受/拒绝/撤回、可见 CAS 首登、首次及过期校园服务隐藏认证、OCR 失败重试，以及只含课表+设置的体验账户。
- [ ] 确认 Apple target 不编译 Rust `/login` 与外部 OCR 链路；Release Archive 会拒绝包含旧 OCR 端点的二进制。
- [x] PAY-01、PAY-03、PAY-05 的客户端签名与 PAY-02 安全键盘兼容逻辑已按 Android `2c33b0b` 隔离实现；协议常量只存在于私有支付兼容层，值不得进入日志、文档、诊断或验收记录。
- [x] CI/自动测试通过应用级禁写开关、runner 域名阻断和 URLProtocol/Mock 禁止连接真实扣款接口。
- [ ] 对照 `PrivacyInfo.xcprivacy` 和 App Store Connect 隐私标签，确认实际数据用途一致。
- [ ] 检查定位、通知、Widget、Quick Look/分享、支付宝跳转与回跳、弱网和取消路径。
- [ ] 固定正式 Bundle ID、签名团队、许可证、版本号、App Icon、支持与隐私政策链接。
- [ ] 生成有签名的 Release Archive，并在 Organizer/App Store Connect 完成最终验证。

## 重签后找不到课表小组件

安大通 Widget 是独立的 `PlugIns/AHUTongWidget.appex`。主 App 能启动不代表扩展被保留；[Sideloadly](https://sideloadly.io/) 提供移除部分或全部扩展的选项，[AltStore](https://faq.altstore.io/altstore-classic/app-ids) 也将扩展计入 App ID 使用量。安装时须保留课表扩展，并在主 App 首次打开后检查系统添加列表。

在重签前检查包结构，重签导出后检查签名与共享权限：

```bash
python3 scripts/verify-widget-bundle.py AHUTong-unsigned.ipa
python3 scripts/verify-widget-bundle.py AHUTong-resigned.ipa --require-signature
```

检查器核对扩展存在、App/Widget Bundle ID 前缀、版本号、可执行文件、双方配置的 App Group，以及签名和描述文件中的共享权限；不会打印描述文件、设备 UDID 或证书。结构检查通过不能替代 iOS 系统注册和真机添加验证。

从源码使用自己团队签名时，设置 `AHUTONG_APP_GROUP` 为该团队已配置并且 App/Widget 都获授权的共享组；两份 entitlements 与两份 Info.plist 共用此变量。仅修改 Bundle ID 而丢失共享权限，会导致组件读不到课表。iOS 的 App/扩展需要共同获授权的 [App Group](https://developer.apple.com/documentation/xcode/configuring-app-groups)。

若系统列表完全没有安大通，先排查扩展保留、扩展签名/标识和注册；若可添加但无数据，再检查共享权限和课表同步。当前本机运行时为 iOS 26.5，不能用模拟器测试替代用户报告的 iOS 27 真机结论。
