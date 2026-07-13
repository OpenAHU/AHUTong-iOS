# AHUTong iOS

AHUTong（安大通）的 iOS 客户端，使用 Swift 和 SwiftUI 逐步迁移 Android 端的校园服务能力。

## 当前基线

- iOS 17+
- Swift 6
- Xcode 26
- XcodeGen 2.45.4+

Bundle ID `com.openahu.ahutong` 目前是工程占位值；签名团队、最终 Bundle ID 和发布参数会在发布前确认。

## 生成并打开工程

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open AHUTong.xcodeproj
```

`project.yml` 是工程配置的唯一来源，生成的 `AHUTong.xcodeproj` 不进入版本控制。

## 验证

```bash
xcodegen generate --spec project.yml
xcodebuild \
  -project AHUTong.xcodeproj \
  -scheme AHUTong \
  -destination 'platform=iOS Simulator,name=<available simulator>' \
  test
```

当前 Windows 工作区无法运行 Xcode；构建、测试与 Archive 由 macOS/Xcode 或 GitHub Actions 验证。

## 迁移进度

长期目标、功能矩阵、风险和逐次变更记录见 [Android → iOS 迁移路线图](docs/migration/android-parity.md)。
