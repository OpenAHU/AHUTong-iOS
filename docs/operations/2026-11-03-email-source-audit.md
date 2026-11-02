# 邮箱字符串与打包来源审计

按用户要求仅查看源码、资源、依赖声明和构建脚本，不解包IPA、不扫描二进制、不读取真实邮箱或Keychain。基线为develop的134377c及本轮feature/shortcuts-fullscreen-scanner。

## 结论

不能声称安装包没有任何人的邮箱。学习资料页RepositoryFooter的“联系”链接明确使用`mailto:1793838025@qq.com`；该链接属于App产品源码，XcodeGen将其编入App，不能因Release剥离符号就认为地址也被删除。本轮仅审计，保留现有联系功能，未自行替换联系人。

| 来源 | 发现 | 对安装包的判断 |
| --- | --- | --- |
| AHUTong/Features/Repository/StudyRepositoryView.swift | 维护者的上述QQ邮箱 | 实际产品联系链接，会进入App |
| AHUTong/Features/StudentMail/StudentMailView.swift | student、reader、teacher的example.test合成地址 | 演示分支及合成邮件与产品源码同文件；普通Release的isDemoSession为false，但不以编译优化推断这些字符串绝对不在包内。这些不是真人邮箱 |
| AHUTongTests、AHUTongUITests | example.test等合成输入 | 独立测试target，不属于Archive中App/Widget的sources或resources |
| Vendor/sdk、Vendor/GuiXu-Rust | 所有受版本控制文本源码、清单及LICENSE/NOTICE未发现邮箱字面量 | 不含项目维护者邮箱；这是源码范围结论，不扩展成所有传递依赖二进制的绝对保证 |
| App中随包的许可证、资源、Widget源码及构建配置 | 未发现其他个人邮箱 | Sentry DSN中的@是URL用户信息分隔符，不是邮箱地址 |
| Sentry 9.31.0对应上游源码 | 运行源码只发现your.email@example.org表单占位值；其余匹配在声明注释 | 不是真人邮箱；App使用自有反馈表单，不启用SDK邮箱输入表单 |

Sentry来源固定为sentry-apple-binaries 9.31.0、Sentry-Static。源代码对照为getsentry/sentry-cocoa的9.31.0 tag（2f64c77f77514acd01780d1aac86ae75b7fccd04）；审计Sources、资源与许可证，未修改依赖。工程使用预编译分发，**只看对应源码不能证明预编译字节与源码完全等同，也不能保证每个未调用占位字符串都已被链接器剥离**。

## 邮箱是否会被收集

AppDiagnostics的SentryFeedback使用name:nil、email:nil，options.sendDefaultPii=false。没有将校园邮箱账号或联系人设置为Sentry用户资料的路径。校园邮箱功能在用户登录后从学校服务读取真实地址，StudentMailStoredSession通过student-mail.session保存在Keychain；这是安装后的业务数据，不是打包时嵌入某个测试账号。

上述结论不等于任何反馈都绝无邮箱：用户自由填写的问题描述可能包含邮箱；明确选择的网络详情也可能含个人查询结果。网络详情默认不选，邮箱正文排除。具体发送边界见[反馈提交链路审计](2026-11-02-feedback-audit.md)。

## 本轮构建约束

App与Widget提升至1.0.8（17）。用户最初要求真机验收前暂停推送与Actions；本机未保留正式贡献密钥配置，说明GitHub Secret不能读回后，用户明确选择“使用Actions构建”。本轮因此只推送feature并手动运行IPA工作流，使用已有CANTEEN_WRITE_KEY及成品配置核验，不创建PR或合入develop/main。没有拿测试密钥或从旧IPA/已安装App提取密钥代替；邮箱审计仍严格只看源码。
