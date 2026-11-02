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
3. 原 CI 对 codex 分支的 push 与开放 PR 同时触发，产生重复完整测试。日常 CI 改为 main/develop push、面向这两者的 PR 及手动运行。IPA/Archive 自动构建改为develop push，配合feature到develop的集成流程；对纯文档/测试改动增加路径过滤，打包流程自身改动仍触发，其他分支可手动构建。IPA上传与其他步骤统一为upload-artifact@v6，移除v4的Node20弃用警告。
4. CI [#189](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/41399624353) 的导航分片未通过：拖动换位两次尝试均出现位置断言失败。截图显示编辑浮层遮挡下方卡片，测试仍直接拖向该卡片中心；本机同源码两项复验通过，不能据此忽略CI失败。测试改为从卡片露出的上部拖放，避开浮层边缘及右上移除按钮，等待两次换位的实际坐标；保留2点误差及双向交换断言。返回按钮按浴室导航栏及系统BackButton明确定位，等待表单可交互后点击，避免只凭页面容器存在就执行返回。
5. #189实时活动分片最终通过，但首次出现fixture空标签及后台进程清理失败。改为匹配“已创建”终态；清理先恢复前台、重新启动清理夹具并等待“已清理”，不拿初始空标签代替完成。课前显示、开始上课后消失及原生倒计时语义不变。

启动测量依据：[Apple XCTApplicationLaunchMetric](https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric)。Actions 路径与分支过滤同时满足才触发，见[官方 workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onpushpull_requestpull_request_targetpathspaths-ignore)。

## 覆盖质量与保留边界

- Swift 单元方法526/600，全部为 XCTest；UI拆分后99项，每项恰好归属一个分片。预算没有把UI/Rust/Python算进Swift，也没有因容量跳过用例。
- 重点抽查会话续期、请求重试、校园码、支付幂等/协议、隐私脱敏、反馈封包、更新去重。多数使用本地 URLProtocol、内存存储、可控时钟；Sentry封包测试实际拦截SDK输出到 `.invalid`，不是只断言配置常量。支付测试检验请求契约及状态流转，不真实付款或贡献写入。
- 部分测试较长是同一笔订单的请求链验证，不能仅因行数删除。固定枚举/协议输入的表格循环合理；与用户界面文案无关的稳定契约断言继续保留。
- SessionRefreshCoordinatorTests 仍用50ms制造并发重叠，另有少量等待 WebKit/系统动画的固定延迟。这是后续稳定性改进项；本轮不向业务接口添加专用观测参数，也不把所有异步等待盲目替换为 sleep。UI关键就绪大多通过 waitForExistence 或谓词等待。
- CI现有UI失败重试会保留两次证据，settings 的旧失败实际重跑了整个分片。绿色但需要重试不能等同首次稳定通过；有重试应查看日志警告和xcresult，而不是持续增加次数。
- 现有 opt-in Sentry smoke 默认跳过是为了禁止普通测试发送生产事件；其非空event ID仅证明SDK接受提交，不能证明后端收到。离线封包与真实收件必须分开报告。后续按用户单独授权进行了只读线上审查，临时令牌已撤销；生产事件明细仅留在本机忽略目录，不纳入公开仓库。
- 现有性能测试收集指标但没有设备校准基线，不能声称已建立启动速度回归阈值。App Group的真机授权、小组件共享、Siri真实语音、第三方扫码协议和真实贡献须独立验收；模拟器通过不能替代这些项目。

## 验证证据

- Python脚本：显式指定Xcode后完整38项全部通过、无跳过，见 `build/audit-20261102/python-tests-xcode.log`。首次默认Command Line Tools导致签名夹具的整个setUpClass跳过，原记录“31通过、1项跳过”误把类级跳过当作一个方法，已补跑并更正。
- Swift预算、99项UI分片覆盖、三个修改工作流的YAML解析与 `git diff --check` 通过。
- 指定 iPhone 17 Pro / iOS26.5，Release优化并开启隔离测试fixture；启动/课表及拆分设置9项全部通过、无跳过、无重试，见 `build/audit-20261102/launch-settings.xcresult`。启动响应5次均收到指标：1.4661、1.3604、1.3495、1.2932、1.3435秒；无校准基线，不代表真机耗时。
- #189的Swift单元阶段通过，服务30项、支付9项首次通过；设置22项和实时活动10项需要一次重试才通过；导航最终27/28通过，不能作为合并绿灯。后续测试修正的本机结果与新CI分别记录，不覆盖这次失败证据。
- 指定iPhone17Pro/iOS26.5的Debug复验中，实时活动5项及工具15项首次通过，见 `build/audit-20261102/tools-live-hardened.xcresult`；初次尝试额外滚动后，换位用例未取得可交互卡片，1项失败的证据保留。撤回该滚动，改用浮层上方实际露出的卡片上部拖放，专项连续3次通过、无失败重试，见 `build/audit-20261102/drag-visible-target.xcresult`。连同前述9项，共30项受影响UI完成本机验证；未改业务布局或降低换位断言。
- 先复验本地变更，再以PR #13最新完整CI为合并门禁；最终状态与合并提交以PR页面为准。业务源码和1.0.7（16）版本号不因本次测试治理改变。

## 收口结果

2026-11-02完整[CI #190](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/41405654435)通过：Swift525通过、1项原有生产收件opt-in跳过，99项UI最终通过。导航分片的工具库取消拖动、换位用例发生过单次重试，其余四个UI分片没有重试警告；仍保留原始日志，不把绿色写成全部首次通过。

PR #13已使用merge commit合入develop，提交134377c；本地develop已快进同步，main和AIO gitlink未修改。合并后的[IPA #150](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/41474375917)与[Archive](https://github.com/OpenAHU/AHUTong-iOS/actions/runs/41474375926)成功。后续扫码/快捷指令从最新develop建立独立feature分支，不继续堆叠旧codex分支。
