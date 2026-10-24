# iOS CI

截至 2026-10-24，完整运行包含 545 条 Swift 单测（显式 Sentry 外部投递默认跳过）、48 条 UI、25 条 Rust 测试及 25 条 Python 检查。以下性能对比是 2026-10-20 的历史结果，使用当时的 509 Swift / 40 UI / 22 Python 范围，不作为新增测试后的当前耗时。

## 实测

比较优化前最后一轮成功运行 [39401198290](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39401198290) 与优化后 [39428134231](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39428134231)。总用时从工作流创建计至最后一个 job 结束，包含排队。

| 指标 | 优化前 | 优化后 |
| --- | --- | --- |
| 总用时 | 29 分 22 秒 | 23 分 58 秒 |
| App / Widget / 测试目标构建次数 | 4 次 | 1 次 |
| 累计 job 用时 | 84 分 16 秒 | 81 分 54 秒 |

本轮总用时缩短 **18.4%**。这是单次完整运行对比；GitHub 提示 macOS arm64 runner 容量紧张，排队、冷启动和辅助功能查询耗时仍会波动。

| 优化后任务 | 用时 |
| --- | --- |
| `Build test products` | 4 分 37 秒 |
| `Test ui-live-activity` | 17 分 29 秒 |
| `Test ui-services` | 15 分 38 秒 |
| `Test ui-navigation` | 18 分 36 秒 |
| `Test ui-settings` | 12 分 47 秒 |
| `Test ui-payments` | 12 分 47 秒 |

## 工作流

- 一次 `build-for-testing`，将 `Build/Products` 和 `.xctestrun` 打为 tar，保留执行权限及符号链接。五个任务下载同一运行的产物，以 `test-without-building` 执行，先核对 Xcode 与 Simulator SDK 版本。
- 导航组先运行全部 Swift 单测，再运行 5 条 UI；校园服务/电话本/邮箱 14、支付 5、实时活动/快捷指令 10、设置/体验 14 条 UI。单测复用导航模拟器，避免第六个 Mac 测试任务排队。
- `.github/ci-test-shards.json` 定义分组；`python3 scripts/ci-test-shards.py validate` 强制每条 UI 恰好分配一次。漏分、重复和失效选择都使 CI 失败；新增类须分配分组，已按类分配的新方法自动进入同组。
- 保留五台隔离模拟器、组内串行、真实课程截止时间等待、原生系统设置操作、支付禁写、域名阻断、截图与 xcresult。保留全部原断言。
- UI 分组发生失败时，XCTest 可以在新测试进程复验整组所选用例一次；并非仅重跑失败方法。两次结果均保留；依靠复验通过时显式发出 warning 并写入工作流摘要，连续失败仍使 CI 失败；Swift/Rust/Python 单测不自动复验。
- UI job 上限为 40 分钟，包含冷启动、单测（导航组）、最多两轮所选 UI 及结果保存。2026-10-23 run 39972435515 的设置/服务组首轮各有一项等待失败，完整重试触及原 25 分钟上限；设置重试 14 项均通过后仍被取消并丢失完整结果包。扩大 job 预算用于完成既有有界重试和保存证据，不增加重试次数、删除断言或放宽失败结论。
- 共享构建包保留 1 天；保留期内可单独重跑失败任务，整轮重跑替换旧共享包。测试证据按 `run_attempt` 分开保存 7 天，保留失败与复验记录。

模拟器首次启动、UI 自动化和真实倒计时等待仍占主要时间。XcodeGen 安装与产物传输仅占数秒至十余秒；缩短真实截止时间等待会改变覆盖范围。

## 验证记录

- 本机：跨目录恢复 tar 后 509 单测通过；通用 Simulator `build-for-testing`、22 Python 检查、40 条 UI 分组审计通过；页面巡检/两条电话本 UI、完整支付巡检分别复验通过。
- 首轮 [39406690279](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39406690279)：构建复用成功，导航组两处失败；修正大字体 Popover 外点位置，并增加 Tab 切换的有界等待。
- 第二轮 [39416825647](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39416825647)：509 单测、39/40 UI 通过。电控菜单首次辅助功能查询超过 8 秒，超出原 5 秒等待；保留选中值断言，将等待上限设为 15 秒，并按逐项耗时再次均衡分组。
- 第三轮 [39420404607](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39420404607)：支付状态首次快照只包含无窗口的 UIApplication 根节点；保留服务端成功条件，允许 45 秒内刷新多个快照，失败增加现场截图。
- [39424819718](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39424819718)：支付通过，快捷指令冷启动遇到 XCTest 激活点无效；改用系统属性等待可点击，并将最多一次、带 warning 和双份证据的复验用于 UI 分组。
- 最终 [39428134231](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39428134231)：509 Swift 单测、40 UI、25 Rust、22 Python 全部通过；40 条 UI 均首次通过，未触发自动复验。
