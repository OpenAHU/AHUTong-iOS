# iOS 发布与设备测试安装清单

## CI 产物

- `iOS CI`：在独立 iPhone 17 Pro Simulator 上构建、运行单元/UI 测试并导出 UI 证据。
- `Build unsigned IPA`：生成不含证书和描述文件的 `AHUTong-unsigned.ipa`，供本机重新签名。
- `Release readiness archive`：生成未签名 `.xcarchive`，校验 App/Widget 的隐私清单、Bundle 结构和敏感材料扫描结果。
- 本轮支付重审的最终代码产物见 `E-20260801-02`：CI `30706286051`、未签名 IPA `30706286050`、Release Archive `30706286068` 均通过；真机扣款仍只允许人工执行。

GitHub Runner 不接收 Apple ID、密码、证书或描述文件。未签名 IPA 不能直接安装到 iPhone，也不等同于 TestFlight/App Store 产物。

## 在 Mac 上使用 Developer Program 安装

已有 Mac、Xcode 和付费开发者账号时，优先从源码用 Xcode 自动签名安装，便于同时管理主 App、Widget 和共享课表权限。此路径会重新构建；安装下载的 IPA 则使用下文的 Sideloadly 重签步骤。

1. 初始化仓库依赖后执行 `xcodegen generate --spec project.yml`，用 Xcode 打开 `AHUTong.xcodeproj`。
2. 在 Xcode 的 Settings → Accounts 登录开发者账号；为 `AHUTong` 和 `AHUTongWidget` 两个 target 选择同一个 Team，并启用 Automatically manage signing。
3. 使用属于自己团队的 App / Widget Bundle ID。为这两个 App ID 启用同一个已注册的 App Group，将工程的 `AHUTONG_APP_GROUP` 设为该组；两份 entitlements 与 Info.plist 会共用此变量。保留这些签名设置在本机，重新生成工程前保存本地配置。
4. 用数据线连接并解锁 iPhone，完成“信任此电脑”；按系统提示在“设置 → 隐私与安全性 → 开发者模式”启用并重启。Xcode 顶部选择 `AHUTong` scheme 和这台 iPhone，按 ⌘R 构建、签名并安装。
5. 首次打开 App、刷新课表，再添加桌面课表组件；在“小工具 → 添加桌面课表微件”检查共享权限。更新已有安装时沿用原 Team 和 Bundle ID；改用新标识会成为另一个安装。

Apple 说明：[在设备上运行](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html)、[为目标分配签名团队](https://help.apple.com/xcode/mac/current/en.lproj/dev23aab79b4.html)、[配置 App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)。签名有效期以实际证书和描述文件为准。

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

1. 从仓库生成 Xcode 工程：`xcodegen generate --spec project.yml`。
2. 用 Xcode 打开 `AHUTong.xcodeproj`，在 App 和 Widget 两个 target 选择自己的 Personal Team。
3. 将 App 和 Widget 的 Bundle ID 改成自己账号下唯一且相互匹配的值。需要共享课表时，两个 target 都须获授权使用同一 App Group，并设置 `AHUTONG_APP_GROUP`；不要提交这些本地签名改动。
4. 用数据线连接 iPhone 13 Pro，选择设备后运行；首次安装需在设备的“VPN 与设备管理”中信任开发者。
5. 免费 Personal Team 通常需要每 7 天重新构建/安装。到期前保留本地项目和相同 Bundle ID，以减少数据迁移影响。

Apple 的[能力支持取决于平台及会员类型](https://developer.apple.com/help/account/capabilities/capabilities-overview)。如果当前团队无法为双方授权 App Group，修改标识字符串本身不能解决共享课表；必须以实际 profile、签名权限和设备结果为准，不能承诺免费重签后完整支持 Widget。

### Sideloadly / AltStore

1. 下载 `AHUTong-unsigned.ipa`，只在本机工具内输入 Apple ID。
2. 由工具使用自己的团队重新签名 App 及内嵌 Widget Extension；免费账号为 Personal Team，付费 Developer Program 账号应选对应团队并为两个 App ID 配置同一 App Group。不要把凭据、签名后的 IPA 或描述文件上传仓库。
3. 安装后验证 App 启动、登录、通知授权、桌面 Widget、付款第三方跳转和返回后的订单核验。

## 发布前人工检查

- [ ] 使用授权校园测试账号验证登录、课表和 PAY-01～05；真实支付只由测试者在明确授权的小额环境中手动确认。
- [ ] 验证隐私 v6 接受/拒绝/撤回、可见 CAS 首登、首次及过期校园服务隐藏认证、OCR 失败重试，以及只含课表+设置的体验账户；邮箱会话应在退出/撤回后清除，Sentry 仅在确认且同意当前政策时启动。
- [ ] 确认 Apple target 不编译 Rust `/login` 与外部 OCR 链路；Release Archive 会拒绝包含旧 OCR 端点的二进制。
- [x] PAY-01、PAY-03、PAY-05 的客户端签名与 PAY-02 安全键盘兼容逻辑已按 Android `2c33b0b` 隔离实现；协议常量只存在于私有支付兼容层，值不得进入日志、文档、诊断或验收记录。
- [x] CI/自动测试通过应用级禁写开关、runner 域名阻断和 URLProtocol/Mock 禁止连接真实扣款接口。
- [ ] 对照 `PrivacyInfo.xcprivacy` 和 App Store Connect 隐私标签，确认实际数据用途一致。
- [ ] 检查定位、通知、Widget、Quick Look/分享、支付宝跳转与回跳、弱网和取消路径。
- [ ] 固定正式 Bundle ID、签名团队、许可证、版本号、App Icon、支持与隐私政策链接。
- [ ] 生成有签名的 Release Archive，并在 Organizer/App Store Connect 完成最终验证。

## 重签后的课表小组件

安大通 Widget 是独立的 `PlugIns/AHUTongWidget.appex`。主 App 能启动不代表扩展被保留；[Sideloadly](https://sideloadly.io/) 提供移除部分或全部扩展的选项，[AltStore](https://faq.altstore.io/altstore-classic/app-ids) 也将扩展计入 App ID 使用量。安装时须保留课表扩展，并在主 App 首次打开后检查系统添加列表。

构建 `iphoneos` 后，必须用打包脚本保留 App/Widget 的 App Group 声明。直接压缩完全无签名的 `.app` 会丢失二进制中的权限声明，重签工具无法从原签名得知共享需求。脚本只使用 ad-hoc 临时签名，不使用开发者证书、不添加 Team ID 或描述文件；生成的 IPA 仍需开发者重签才能安装。

```bash
python3 scripts/package-resignable-ipa.py /path/to/AHUTong.app AHUTong-unsigned.ipa
python3 scripts/verify-widget-bundle.py AHUTong-unsigned.ipa --require-entitlements
python3 scripts/verify-widget-bundle.py AHUTong-resigned.ipa --require-signature
```

检查器核对扩展、标识、版本、App Intents 元数据和双方权限声明；重签检查还要求最终签名、描述文件和团队一致。重签保留原组时使用原组；改名时只接受双方描述文件中唯一的共同组，且最终签名都必须授权该组。不会打印描述文件、设备 UDID 或证书。CI 的 IPA 工作流使用同一脚本，并强制验证权限声明，避免仅检查包结构就放行。

从源码使用自己团队签名时，设置 `AHUTONG_APP_GROUP` 为该团队已配置并且 App/Widget 都获授权的共享组；两份 entitlements 与两份 Info.plist 共用此变量。仅修改 Bundle ID 而丢失共享权限，会导致组件读不到课表。iOS 的 App/扩展需要共同获授权的 [App Group](https://developer.apple.com/documentation/xcode/configuring-app-groups)。

### Sideloadly + Developer Program 账号（macOS / Windows）

1. 从 [Sideloadly 官网](https://sideloadly.io/) 下载对应系统的版本，用数据线连接并信任 iPhone，在工具中选择该 iPhone、载入 `AHUTong-unsigned.ipa`，使用开发者账号重签安装。保留 Widget 扩展，并沿用原安装标识覆盖更新；无需卸载或清空数据。
2. 打开 App 刷新课表，然后检查桌面组件。原共享组不能访问时，App/Widget 会尝试识别同一签名团队的唯一共同授权组；仍须通过系统 `containerURL` 检查，不会改用无法共享的私有目录。
3. 若仍不能同步，进入“小工具 → 添加桌面课表微件 → 添加”，查看具体原因并使用“分享安装检查”。摘要只包含版本、App/Widget 标识、共享组和检查结果；不包含账号、Cookie、课表、设备标识、证书或完整描述文件，不需要导出签名 IPA。
4. `noCommonGroup` 表示两份描述文件未提供共同组，`accessDenied` 表示系统未允许访问所选组。Developer Program 会员身份本身不代表本次签名已配置 App Groups。在 Apple Developer 后台为本次安装的两个实际 App ID 启用同一个、属于自己团队的 App Group，并让签名工具重新生成匹配描述文件及双方 entitlement。不要直接假定原 `group.com.openahu.ahutong.shared` 已属于自己的团队。
5. Sideloadly 官方将“自定义 app entitlements”列为 Developer Program 账号可用的 Patreon 功能；不能把“登录 Developer 账号”当作这项签名能力已启用的证据。若当前签名流程无法保留/设置双方共享权限，可改用自己团队的 Xcode 签名或支持该配置的签名流程，不能靠 App 代码绕过系统权限。

运行时对 `embedded.mobileprovision` 的读取仅用于侧载兼容候选和诊断；格式变化或缺失时回到配置组/明确不可用状态。Apple 提醒该格式不是稳定产品 API，因此不把读取成功当作签名验证，更不将其当作共享授权。正常签名和 App Store 构建直接使用配置组，无需读取描述文件。

参考：[Apple 注册 App Group](https://developer.apple.com/help/account/identifiers/register-an-app-group/)、[启用 App ID 能力](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/)、[Provisioning Profiles 格式与边界](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)、[Sideloadly 更新记录](https://sideloadly.io/changelog)。

若系统列表完全没有安大通，先排查扩展保留、扩展签名/标识和注册；若可添加但无数据，再检查共享权限和课表同步。当前本机运行时为 iOS 26.5，不能用模拟器测试替代用户报告的 iOS 27 真机结论。

2026-10-22 维护：App 和 Widget 每次访问时重新解析共享容器，不固定保存一次失败结果；快照显式设置首次解锁后可读，安装检查无论成功/失败均可分享。这些改动改善进程与锁屏状态下的恢复，不会给缺失权限的重签安装授予 App Group。

2026-10-23 维护：可以添加但课程为空时，也需检查同步数据。仅有起止周范围的课程现与 App 使用同一有效周次；有效缓存会先于网络周次校准发布。“小工具 → 添加桌面课表微件 → 添加”可查看已同步周次/课程数量，并打开课表同步。分享安装检查附带快照状态及数量，不含课程名称/地点；测试课表写入独立私有目录，不覆盖真实共享快照。修复这些数据问题不代表给重签安装授予共享权限。

2026-10-23 用户安装摘要复查：主 App 描述文件没有任何 App Group，Widget 描述文件不可读，系统容器不可访问。v2 检查将其明确归类为 `appGroupNotProvisioned`；描述文件不齐时团队比较为 `unknown`，不能误判为团队不同。此安装必须在签名阶段补齐共享授权，重复打包未签名 IPA 不会修复已安装的描述文件。

### Sentry 诊断与调试符号

SDK 9.31.0 已连接 `ratatoskr / ahutong-ios`。当前隐私 v6 确认后才启用过滤后的诊断，普通测试不发事件；真实合成收件和数据边界见 [Sentry 运维说明](../operations/sentry.md)。2026-10-24 用户已授权创建 CI 令牌并保存为仓库 `SENTRY_AUTH_TOKEN`；IPA 与 Archive 的 App / Widget dSYM 自动上传及服务端处理均通过，项目页面可见对应 Debug ID。历史合成 Debug 事件未上传其对应 Debug dSYM，不将 Release 上传成功当作该历史事件已完成源码定位。
