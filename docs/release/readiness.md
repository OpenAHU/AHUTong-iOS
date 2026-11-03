# IPA 安装与签名

## 获取 IPA

在 [Build unsigned IPA](https://github.com/OpenAHU/AHUTong-iOS/actions/workflows/ios-unsigned-ipa.yml) 下载成功运行的 `AHUTong-unsigned-ipa` 附件。IPA 是重签输入，不能直接安装；dSYM 单独保留并上传 Sentry。

## Sideloadly / AltStore

1. 使用自己的 Apple 开发者账号重签 IPA，保留 `PlugIns/AHUTongWidget.appex`。
2. 在工具内完成账号验证并安装；不要把账号密码、证书、描述文件或签名后的 IPA 上传仓库。
3. 更新已有安装时沿用原团队、Bundle ID 和 Keychain 授权，保留应用数据。有效期取决于实际账号、证书和描述文件。

## Xcode 安装

1. 按 README 初始化依赖、生成工程，在 Xcode 中登录开发者账号。
2. 为 App 与 Widget 选择同一团队及获授权的标识，连接并解锁 iPhone，按系统提示完成信任和开发者模式设置。
3. 选择 `AHUTong` scheme 与设备后运行。安装到已有 App 时不要随意更改标识；新建标识或共享组需维护者明确授权。

## 小组件

课表同步需要 App 与 Widget 的最终签名和描述文件均获授权使用同一个 App Group。仅保留扩展、声明相同组名或拥有 Developer Program 账号，不代表本次签名已具备共享权限。

- 添加列表没有安大通：检查扩展是否保留、签名及标识是否有效，首次安装后先打开主 App。
- 可以添加但无课表：在 App 刷新课表，再打开“小工具 → 课表小组件”检查共享状态。“分享安装检查”不包含账号或课程内容。
- 共享组不可用：检查双方实际 App ID、profile 与 entitlement。修改字符串或重新加载时间线不能授予系统权限。

设备包构建后用 `scripts/package-resignable-ipa.py` 打包，脚本从内到外处理嵌套代码并保留共享声明。最终开发者签名后运行 `scripts/verify-widget-bundle.py <App或IPA路径> --require-signature --require-release`；声明检查不能替代真机共享验收。
