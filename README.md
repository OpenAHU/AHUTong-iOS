# 安大通 iOS

安大通的 iOS 客户端，提供课程表与校园服务，支持 iOS 17 及以上版本。

## 下载与使用

1. 登录 GitHub，进入 [Build unsigned IPA](https://github.com/OpenAHU/AHUTong-iOS/actions/workflows/ios-unsigned-ipa.yml)，打开最近一次成功的运行。
2. 在 **Artifacts** 下载 `AHUTong-unsigned-ipa` 压缩包，解压得到 `AHUTong-unsigned.ipa`。构建产物保留 7 天。
3. 使用 Sideloadly 或 AltStore 在自己的电脑上重签并安装，保留内嵌 Widget 扩展。安装后打开安大通，按首启流程完成登录。

IPA 需要重新签名才能安装。签名、安装与课表小组件配置见 [安装说明](docs/release/readiness.md)。

校园邮箱位于“小工具 → 校园邮箱”。列表、阅读、写信、联系人及附件使用原生界面；复杂富文本或云附件可从右上角进入“邮箱网页版”。首次更新至隐私政策 v5 时需重新确认邮箱数据用途，已有登录会话不会因此清空。

## 开发

需要 macOS、Xcode 26+、XcodeGen 2.45.4+ 和 Rust stable。

```bash
git clone --recurse-submodules https://github.com/OpenAHU/AHUTong-iOS.git
cd AHUTong-iOS
xcodegen generate --spec project.yml
open AHUTong.xcodeproj
```

在 Xcode 中选择 `AHUTong` scheme 和 iPhone Simulator，运行或测试。`project.yml` 是工程配置来源，生成的 Xcode 工程不提交。

[功能与验证记录](docs/migration/android-parity.md) · [CI 耗时分析](docs/ci.md)
