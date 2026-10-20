# iOS CI 耗时

以 [PR #8 的首轮运行](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/39389808697) 为样本，四个 job 并行执行，总耗时约 30 分钟，由最长的 `ui-settings` 决定。

| 测试组 | 总耗时 | 模拟器启动 | 编译及测试准备 | 实际测试 |
| --- | --- | --- | --- | --- |
| unit | 6 分 43 秒 | 1 分 41 秒 | 3 分 54 秒 | 509 项，8 秒 |
| ui-navigation | 17 分 51 秒 | 4 分 9 秒 | 6 分 54 秒 | 5 项，5 分 47 秒 |
| ui-services | 21 分 22 秒 | 2 分 46 秒 | 5 分 33 秒 | 7 项，10 分 36 秒 |
| ui-settings | 30 分 8 秒 | 2 分 45 秒 | 7 分 7 秒 | 28 项，17 分 53 秒 |

“编译及测试准备”按 `Build and test` 开始至 XCTest suite 开始计算；总耗时还包含依赖准备、测试结束清理和上传。该轮设置组有两项岛卡自动化失败，排查、本机复验与整套重跑增加了本次处理的等待时间。

- 当前四个 job 各自启动全新模拟器并编译 App、Widget 和测试目标，仅缓存 Rust 依赖，没有复用 Xcode 构建结果。云端机器和首次启动的耗时存在明显波动。
- `-parallel-testing-enabled NO` 使各组 UI 用例串行运行。设置组包含最多用例；课程倒计时还需等待真实截止时间，不能通过缩短等待来保持同等覆盖。
- 此样本安装 XcodeGen 仅需 3–6 秒，产物上传为 2–17 秒，都不是主要瓶颈。

本次优化保留全部测试覆盖和独立模拟器，实施下述构建复用与均衡分组。


## 构建复用与分组

工作流现在先执行一次 `build-for-testing`，将 `Build/Products` 与 `.xctestrun` 打为 tar 包，随后各测试 job 下载同一运行的产物，使用 `test-without-building`。tar 保留执行权限与符号链接；测试端核对 Xcode 和 Simulator SDK 版本。测试 job 不再安装 XcodeGen、编译 Rust 或拉取子模块。

单元测试保持全量运行；40 条 UI 测试分为导航 7、校园服务 3、支付 8、实时活动/快捷指令 9、设置/体验 13 条。分组按既有耗时平衡，不按条数平均。`.github/ci-test-shards.json` 定义分组，`python3 scripts/ci-test-shards.py validate` 强制每条 UI 用例恰好出现一次。增加测试类时必须分配分组；已按类分配的新方法自动进入同组。

各组仍使用独立模拟器、组内串行；保留 509 条 Swift 单测、40 条 UI、25 条 Rust 测试、支付保护、截图与 xcresult。Python 检查由 16 条增至 22 条。共享构建包保留 1 天，测试证据保留 7 天。
