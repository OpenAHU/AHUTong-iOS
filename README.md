# 安大通 iOS

安大通的 iOS 客户端，提供课程表与校园服务，支持 iOS 17 及以上版本。

## 下载与使用

1. 登录 GitHub，进入 [Build unsigned IPA](https://github.com/OpenAHU/AHUTong-iOS/actions/workflows/ios-unsigned-ipa.yml)，打开最近一次成功的运行。
2. 在 **Artifacts** 下载 `AHUTong-unsigned-ipa` 压缩包，解压得到 `AHUTong-unsigned.ipa`。构建产物保留 7 天。
3. 使用 Sideloadly 或 AltStore 在自己的电脑上重签并安装，保留内嵌 Widget 扩展。安装后打开安大通，按首启流程完成登录。

IPA 需要重新签名才能安装。签名、安装与课表小组件配置见 [安装说明](docs/release/readiness.md)。

小工具按四个分类呈现双列浅底描边卡片，支持按压反馈、系统搜索和原生导航；固定到首页的工具也会保留。新增教务考勤和只读必吃榜，课表小组件添加与同步检查位于“小工具 → 添加课表小组件”。

校园邮箱位于“小工具 → 校园邮箱”。列表、阅读、写信、联系人及附件使用原生界面；复杂富文本或云附件可从右上角进入“邮箱网页版”。

隐私政策 v7 在稳定性诊断之外增加抽样性能、随机安装日活及主动反馈。更新后需重新确认，已有登录会话不会因此清空；只有同意当前政策才启动诊断。网络详情默认不选，提交前需逐次预览；密码、验证码、校园码、支付及邮箱正文不采集。数据边界见 [隐私数据用途](docs/release/privacy-data-map.md)。

课表右上角设置可开启“每周开始于周日”，默认关闭；开启后按周日到周六连续展示，课程日期保持不变。

## 开发

需要 macOS、Xcode 26+、XcodeGen 2.45.4+ 和 Rust stable。

```bash
git clone --recurse-submodules https://github.com/OpenAHU/AHUTong-iOS.git
cd AHUTong-iOS
xcodegen generate --spec project.yml
open AHUTong.xcodeproj
```

在 Xcode 中选择 `AHUTong` scheme 和 iPhone Simulator，运行或测试。`project.yml` 是工程配置来源，生成的 Xcode 工程不提交。

Swift 单元测试上限为 600，运行 `python3 scripts/check-swift-test-budget.py`；UI、Python 和 Rust 不计入。测试按风险保留独立场景，具体规则见 [AGENTS.md](AGENTS.md)。本机预览使用 iPhone 17 Pro；Xcode 27 的设备窗口位于 Device Hub。IPA 是真机包，模拟器须构建同源码的 Simulator App。

[最新 Android 差距审计](docs/migration/2026-10-26-android-gap-audit.md) · [考勤、必吃榜与续期记录](docs/migration/2026-10-26-campus-services.md) · [测试清理依据](docs/migration/2026-10-26-test-audit.md)

[功能与验证记录](docs/migration/android-parity.md) · [CI 耗时分析](docs/ci.md)
