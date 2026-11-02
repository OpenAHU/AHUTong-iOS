# 2026-11-02：分支与测试质量审查

维护目录固定为 `/Users/himekawa/Projects/AHUTong/iOS`。本次审查起点为 `0f435ce`，远端 develop 为 `d063481`，main 为 `9e8478a`；不修改 AIO gitlink，不执行生产发版。

## 分支判断

按需补充浅克隆历史后，对所有远端分支和本地分支检查祖先关系。只有 PR [#13](https://github.com/OpenAHU/AHUTong-iOS/pull/13) 仍开放，目标为 develop，无文件冲突。功能通过该 PR 集成到 develop；main 保留稳定基线。旧 codex 分支沿原 PR 收口，新任务采用 feature/<目标>，避免为了改名重复整理已推送历史。

以下历史分支不是 develop 的祖先，但文件树与对应 squash 合并提交完全相同，不能仅凭 `git branch --merged` 或逐提交 patch ID 判断仍缺功能：

| 历史分支 | 已合并位置 |
| --- | --- |
| codex/ios-native-ui-campus-code | #6 / 8b2916c |
| codex/ios-widget-resigning | #7 / 0153ef1 |
| fix/island-phonebook-ui、chore/1.0.3-maintenance | #8 / e9b7704 |
| perf/ci-runtime | #9 / 6b843b7 |
| codex/ios-reliability-mail-theme | #10 / 9e8478a |
| codex/ios-widget-navigation-reliability | #11 / f7a79e0 |

其余旧功能分支已是 develop 的祖先，包括 feat/live-activity-countdown、早期迁移/支付/续期和授权分支；本地独有的 canteen-records、native-motion、wallpaper 分支也已包含在 develop。没有重复合并这些旧分支，也没有强制推送或删除历史分支。当前远端 refs 快照保存在忽略目录 `build/audit-20261102/branch-refs.txt`。

## 已发现并处理

1. CI [#188](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/40915426807) 的 settings 分片实际为19项：18通过，启动性能测量1项失败。两次尝试均为 XCTest 指标缺失（第4/第3次迭代为0个指标），不是首页断言失败或性能超过阈值。原测试在测量块中立即 terminate，可能过早结束响应指标采集；改为只测 launch，待 XCTest 收集后检查首页。保留5次迭代和 waitUntilResponsive，不跳过、不放宽断言、不减少采样次数。下一次 launch 自身会先结束旧进程。名称改为 testLaunchPerformance，不把默认 Debug CI 测量误称为 Release。
2. 原 Settings 综合测试串联 Tab 顺序、隐藏 Debug、偏好位置、清数据、更新说明和小组件引导，故障定位困难且覆盖重复。拆成 Tab、账户/隐私位置、取消清数据、关闭更新说明四项；隐藏 Debug 和小组件引导保留既有专用回归，避免重复操作。未将独立场景塞进更大的方法。
3. 原 CI 对 codex 分支的 push 与开放 PR 同时触发，产生重复完整测试。日常 CI 改为 main/develop push、面向这两者的 PR 及手动运行。IPA/Archive 对纯文档/测试改动增加路径过滤，打包流程自身改动仍触发；手动构建保留。

启动测量依据：[Apple XCTApplicationLaunchMetric](https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric)。Actions 路径与分支过滤同时满足才触发，见[官方 workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onpushpull_requestpull_request_targetpathspaths-ignore)。

## 覆盖质量与保留边界

- Swift 单元方法526/600，全部为 XCTest；UI拆分后99项，每项恰好归属一个分片。预算没有把UI/Rust/Python算进Swift，也没有因容量跳过用例。
- 重点抽查会话续期、请求重试、校园码、支付幂等/协议、隐私脱敏、反馈封包、更新去重。多数使用本地 URLProtocol、内存存储、可控时钟；Sentry封包测试实际拦截SDK输出到 `.invalid`，不是只断言配置常量。支付测试检验请求契约及状态流转，不真实付款或贡献写入。
- 部分测试较长是同一笔订单的请求链验证，不能仅因行数删除。固定枚举/协议输入的表格循环合理；与用户界面文案无关的稳定契约断言继续保留。
- SessionRefreshCoordinatorTests 仍用50ms制造并发重叠，另有少量等待 WebKit/系统动画的固定延迟。这是后续稳定性改进项；本轮不向业务接口添加专用观测参数，也不把所有异步等待盲目替换为 sleep。UI关键就绪大多通过 waitForExistence 或谓词等待。
- CI现有UI失败重试会保留两次证据，settings 的旧失败实际重跑了整个分片。绿色但需要重试不能等同首次稳定通过；有重试应查看日志警告和xcresult，而不是持续增加次数。
- 现有 opt-in Sentry smoke 默认跳过是为了禁止普通测试发送生产事件；其非空event ID仅证明SDK接受提交，不能证明后端收到。离线封包与真实收件必须分开报告。没有本轮生产事件查询，不用历史事件代替当前问题清单。
- 现有性能测试收集指标但没有设备校准基线，不能声称已建立启动速度回归阈值。App Group的真机授权、小组件共享、Siri真实语音、第三方扫码协议和真实贡献须独立验收；模拟器通过不能替代这些项目。

## 验证证据

- Python脚本：本地32项，31通过、1项环境条件跳过，见 `build/audit-20261102/python-tests.log`。
- Swift预算、99项UI分片覆盖、三个修改工作流的YAML解析与 `git diff --check` 通过。
- 指定 iPhone 17 Pro / iOS26.5，Release优化并开启隔离测试fixture；启动/课表及拆分设置9项全部通过、无跳过、无重试，见 `build/audit-20261102/launch-settings.xcresult`。启动响应5次均收到指标：1.4661、1.3604、1.3495、1.2932、1.3435秒；无校准基线，不代表真机耗时。
- 先复验本地变更，再以PR #13最新完整CI为合并门禁；最终状态与合并提交以PR页面为准。业务源码和1.0.7（16）版本号不因本次测试治理改变。
