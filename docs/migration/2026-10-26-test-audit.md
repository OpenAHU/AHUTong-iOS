# Swift 单元测试与不可达代码审计（2026-10-26）

用户确认 **500 上限只限制 Swift 单元测试**；UI、Python、Rust 不计入。`scripts/check-swift-test-budget.py` 按 `AHUTongTests/**/*.swift` 中无参数 XCTest `test…` 方法保守统计，包括条件编译源码，目前 **500 / 500**（本轮开始为 549）。CI 在构建前执行同一检查。

没有合并不相关用例、改名隐藏测试、增加 skip 或将单测转为 UI 来绕过限制。Sentry 真实收件测试原先就要求显式 opt-in，普通验证继续跳过，避免发送事件。

## 代码删除依据

- `PaymentAcceptance.swift`：Debug 入口删除后，`CMBRechargeView` 的两个生产调用点都只走默认 live；没有调用方选择 `noDebitAcceptance`。删除旧 HEAD 探测/报告/专用输运及 View 的不可达分支。真实校方 WebView、Cookie 引导、学校/银行白名单、凭据外泄拦截、关闭清理均保留。
- `APIClient.swift` / `APIRequest.swift`：原型仅被自身测试调用；真实服务使用 `NetworkTransport` 及各业务客户端。将仍被生产使用的 `NetworkError` 原样移至 `NetworkTransport.swift`。
- Tools 原来自带首页布局 JSON 读取与已固定工具过滤，最新 Android 已明确不再过滤；删除此状态和异步读取。所有工具使用枚举穷尽分支，删除不可达的默认占位页，不改业务目的地。

招行安全测试没有随旧探针整体丢弃：双重编码凭据、路径凭据、嵌套 CAS ticket、深层转义、银行自有 token 和内部端口限制这 **6 个有效回归**移入现有 `CMBRechargeSecurityTests`，仍逐个独立运行。原文件另一项 WebView 临时存储测试与现有用例重复，保留后者；固定错误文案测试删除。

## 删除明细

每行对应一个原测试，合计 49 项。真实协议解析、订单不可逆阶段、并发与过期回写、认证续期、隐私清理、课程日期和 Widget 时间线等行为测试继续保留。

| 原文件 | 原方法 | 删除理由 |
| --- | --- | --- |
| `PaymentAcceptanceTests.swift` | `testProbeUsesOnlyManualHEADAndExportsNoCredentials` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testUnsafeRedirectFailsClosedWithoutFollowingOrExportingQuery` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testFakeChargeSubstringCannotPassExactRouteContract` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testTransportResponseURLMismatchFailsClosed` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testFailureIsStickyAndCannotBeOverwrittenByLaterSuccess` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testPhysicalDeviceConclusionIsDistinctFromSimulator` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testTransportConfigurationIsEphemeralAndCookieFree` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testEntryURLContractRejectsWhitespaceTokenAndFragment` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testCookieHeaderRejectsControlAndSeparatorCharacters` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testResponseCookieDeletionNeverKeepsEmptyOrExpiredValues` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testNoRedirectDelegateRejectsProposedRedirect` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testURLSessionTransportReturnsOriginal302Response` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testDemoFactoryUsesDeterministicInProcessTransport` | unreachable HEAD acceptance mode after removal of Debug entry |
| `PaymentAcceptanceTests.swift` | `testLiveWebConfigurationIsNonPersistentAndHasNoAcceptanceScript` | duplicate of retained CMBRechargeSecurityTests/testWebConfigurationAndCredentialPolicyAreNonPersistent |
| `PaymentAcceptanceTests.swift` | `testInvalidCookiePayloadHasDedicatedNonSensitiveError` | fixed error-copy assertion; bootstrap guards remain unchanged |
| `APIClientTests.swift` | `testClientBuildsRequestAndDecodesResponse` | unused prototype API client |
| `APIClientTests.swift` | `testClientRejectsNonSuccessStatus` | unused prototype API client |
| `AppTabTests.swift` | `testPrimaryTabsMatchAndroidOrder` | constant/asset snapshots covered by native tab UI smoke |
| `AppTabTests.swift` | `testEveryTabHasABundledTemplateIcon` | constant/asset snapshots covered by native tab UI smoke |
| `AppBrandingTests.swift` | `testSplashRendersWithBundledAppIconInBothAppearances` | non-nil image renders; actual simulator previews retain visual evidence |
| `LicenseCatalogTests.swift` | `testCatalogDescribesIOSAndRustDependenciesRatherThanAndroidLibraries` | static catalog snapshots; bundled attribution test retained |
| `LicenseCatalogTests.swift` | `testGuiXuProvidesOfflineLicenseAndNoticeDocuments` | static catalog snapshots; bundled attribution test retained |
| `ContributorsCatalogTests.swift` | `testCatalogPreservesAliasesAndIncludesMaintainersWithTheirCohorts` | mutable contributor catalog snapshots; complete contact URL contract retained |
| `ContributorsCatalogTests.swift` | `testPartnerHasNoExternalRepositoryDestination` | mutable contributor catalog snapshots; complete contact URL contract retained |
| `LoadableStateTests.swift` | `testLoadingStateIsReported` | trivial getter/derived Equatable assertions; feature state tests retained |
| `LoadableStateTests.swift` | `testLoadedStateExposesValue` | trivial getter/derived Equatable assertions; feature state tests retained |
| `LoadableStateTests.swift` | `testErrorsAreEquatableForDeterministicRendering` | trivial getter/derived Equatable assertions; feature state tests retained |
| `AndroidThemeColorTests.swift` | `testARGBHexIgnoresAlphaAndKeepsRGBComponents` | fixed palette helper examples; default/migration behavior retained |
| `AndroidThemeColorTests.swift` | `testInvalidHexFallsBackToAndroidBrand` | fixed palette helper examples; default/migration behavior retained |
| `PhoneBookTests.swift` | `testDirectoryMatchesAndroidCategoriesAndTraceableSource` | mutable dataset snapshot and redundant empty search; native search UI retained |
| `PhoneBookTests.swift` | `testBlankSearchHasNoSyntheticResults` | mutable dataset snapshot and redundant empty search; native search UI retained |
| `HomeWidgetLayoutTests.swift` | `testToolsFollowAndroidRegistryOrderAndRestoreRemovedPaymentWidgets` | obsolete tools subtraction contract and fixed demo copy; live timeline behavior retained |
| `HomeWidgetLayoutTests.swift` | `testCourseSummaryMatchesAndroidOngoingCourseAtFixedBaselineTime` | obsolete tools subtraction contract and fixed demo copy; live timeline behavior retained |
| `FreeClassroomTests.swift` | `testDemoRemoteUsesAllBuildingsWhenNoFilterIsSelected` | demo dataset assertions; official query/decoding and stale request tests retained |
| `FreeClassroomTests.swift` | `testDemoRemoteFiltersSelectedBuildings` | demo dataset assertions; official query/decoding and stale request tests retained |
| `PaymentTests.swift` | `testCardRechargeFixtureUsesNonProductionAccountAndBalance` | demo-only fixture constants; production payment flow and safety tests retained |
| `PaymentTests.swift` | `testBathroomFixtureKeepsPhoneLookupAndDistinctAccounts` | demo-only fixture constants; production payment flow and safety tests retained |
| `PaymentTests.swift` | `testElectricityFixtureProvidesCompleteSelectionPath` | demo-only fixture constants; production payment flow and safety tests retained |
| `NewPaymentFeatureTests.swift` | `testDemoFixtureCoversCompleteReadyStateWithoutProductionAccount` | demo-only fixture contract; official load and protocol tests retained |
| `LostFoundTests.swift` | `testDemoRemotePaginatesWithoutDuplicates` | demo datasource pagination; official ownership/query behavior retained |
| `ScheduleShortcutTests.swift` | `testTeachingWeekParsingNeverDefaultsMissingOrUnrelatedDataToWeekOne` | duplicated TeachingWeekParser coverage in StartupScheduleRegressionTests |
| `ScheduleShortcutTests.swift` | `testTeachingWeekParserSupportsKnownResponseShapes` | duplicated TeachingWeekParser coverage in StartupScheduleRegressionTests |
| `StudyRepositoryServiceTests.swift` | `testCatalogMatchesSixAndroidSourceRepositories` | hardcoded source catalog snapshot; actual remote/download contracts retained |
| `ReleaseOperationsTests.swift` | `testNonSensitiveOperationalMessageIsPreserved` | trivial unchanged logger string; privacy/redaction regressions retained |
| `AndroidParityIconTests.swift` | `testRequiredToolAndSettingsSymbolsExist` | static SF Symbol inventory, covered by simulator native UI previews |
| `HomeWidgetLayoutTests.swift` | `testDefaultMatchesAndroidHomeWidgets` | default slot snapshot; pinned payment navigation covered by Tools UI test |
| `LoadableStateTests.swift` | `testDebugEndpointUsesDeterministicCommandLineOverride` | test injection getter only; feature UI fixtures exercise actual injected states |
| `HomeWidgetLayoutTests.swift` | `testCourseSummaryReportsNextAndFinishedStates` | fixed demo text/time snapshot; current/upcoming/completed timeline and live activity planner retained |
| `FreeClassroomTests.swift` | `testViewModelMaintainsMultiSelectAndSearchState` | demo source returns unfiltered fixture; production request filter and native UI tests retained |

## 验证口径

本轮使用 Xcode 27.0、iPhone 17 Pro / iOS 26.5；在 Release 优化配置中显式启用隔离测试夹具及 testability，覆盖 -Osize 下的逻辑；最终分发 Archive 不含 DEBUG 条件或夹具入口。进一步比较源码与实际发现的方法，找到 `testYCardLoginHTMLRefreshesOnceAndSecondRejectionStops` 错放在 API Stub actor 内，先前不会被 XCTest 发现；将其原样移回 OfficialPaymentReadOnlyDataSourceTests，保持 500 上限并恢复一次续期/二次拒绝的真实回归。源码预算与 XCTest 发现数量均须报告，不以隐藏、错放或条件编译放宽上限。

复验确认三类旧假设：固定日期课程可见性、用自绘按钮的 44pt 可见框推断系统工具栏触控范围、以滚动屏外的天气行判断导航是否回根页。分别以已有课程详情专项、原生工具栏动作验证、根列表及详情消失断言替代。

UI 原先针对急切加载网格直接点击，现在使用系统 List 的可见行滚动；没有放宽目标页面断言。新增三个独立 UI 场景：保留首页固定工具入口、邮箱搜索及返回、无结果的系统空态。旧“添加桌面课表微件”静态卡片断言已改为真正可点的引导入口。

原 195 行跨功能主界面链路拆为首启和各服务路由；已由电话本、设置、课程详情、校园码、贡献浮窗、小组件专项覆盖的重复步骤删除。原 102 行支付链路拆为招行偏好、校园卡、浴室、电控及无 Debug 入口检查；加载/空/错按功能拆分，并检查具体状态内容，删除只验证首页标题的重复遍历。UI 分片清单同步，所有 67 个 UI 方法恰好分配一次。

最终实际发现 500 项单测：499 通过、1 项显式 Sentry 收件跳过、0 失败；actor 内错放测试已运行并通过。相关 UI 共 45 个不重复方法通过，最终复验 30 项全绿。

测试结果与截图路径见主路线图 E-20261026-01；生成的日志、xcresult、IPA 和 dSYM 位于被忽略的 build 目录，不提交。未来增加单测前先审计现有用例，不把 500 当作需要每轮填满的目标。

## 双列卡片与新业务切片的后续调整

用户否定 List 后恢复紧凑网格；根节点验证改用 `tools.grid` 的 ScrollView，保留系统搜索和精确目的页断言。新增 6 项 UI 场景，当前 73 个 UI 方法恰好分片一次。此前 List 验证属于历史切片，最终网格另外验证。

新增 10 个独立单元测试：OCR 无效结果后重取并带轮换 Cookie、校方验证码拒绝后重取、5 次上限且不提交凭据、10012 凭据错误立即停止；考勤真实缺勤日期、拒绝外部跳转、SSO 脚本回调及 HTTP 401 后换一次 JWT；必吃榜公共请求契约、缓存/手动刷新、迟到响应隔离。

对应删减 10 个低价值测试，未搬入 UI 或合并进其他方法以规避预算。它们不都属于失效测试，依据如下：

| 方法 | 审查结论与删除依据 |
| --- | --- |
| `AndroidThemeColorTests/testDefaultIsAuroraBlueAndPreviousDefaultRemainsSelectableAsIrisPurple` | 色板常量/数值镜像，一次包含过多条目；主题仍须目视验收 |
| `SettingsInteractionTests/testPressedStateIsVisiblyDistinctFromRestingState` | 直接读取反馈参数，不能证明真实触控反馈；保留原生交互验证 |
| `SettingsInteractionTests/testReduceMotionKeepsGeometryWhileRetainingNonMotionFeedback` | 同上，保留系统设置适配，无障碍专项另行验收 |
| `AppDiagnosticsTests/testPrivacyExplainsDiagnosticsAndRequiresNewConsent` | 固定文案及版本数字断言；真实同意/撤回与脱敏测试保留 |
| `WeatherRepositoryTests/testCompactHomePresentationUsesWeatherCodeAndMetrics` | 固定字符串与图标样本；协议、定位、缓存和天气点击测试保留 |
| `CampusGradeParserTests/testGradeProfileDisplayNameMatchesAndroidFallbacks` | 显示名称样本；多学籍隔离、字段解析和页面筛选保留 |
| `StudyRepositoryServiceTests/testRepositoryDisplayPathUsesCollegeNameAndRemovesDuplicatedRoot` | 固定显示路径；目录、面包屑目标、下载及安全用例保留 |
| `SchoolCalendarRepositoryTests/testViewModelReportsPhotoSaveCompletion` | stub 的成功消息和参数转发，未覆盖系统照片写入；保留下载/图片/缓存测试，照片保存须系统 UI 验收 |
| `CampusExamDisplayStatusTests/testShortensThreePartAndroidLocationButPreservesOtherFormats` | 两个地点显示样本；日期/状态、查询和详情 UI 保留 |
| `GradeViewModelTests/testGradeResultDisplayRemovesHTMLMarkup` | 显示文本样本；gradeDetail-only 解析仍覆盖清理后文本，纯文本显示实现保留 |

累计删除 59、新增 10，净减少 49；源码上限仍 500，不声称所有被删项已经过时。后续完整单测实测发现并执行 500 项：499 通过，1 个原有显式 Sentry 收件 opt-in 按设计跳过，0 失败（最终 `campus-final-unit.xcresult`，包含推荐项无 rank 响应）。

## 用户参考图确定分类卡片后的调整

“默认字号一屏内全部 16 项可点”的 UI 假设被四分类标题的新设计取代，原 `testAllSixteenServicesAreVisibleWithoutScrollingAtDefaultTextSize` 更名为 `testCategoryCardsUseTwoColumnsAndLearningRemainsReachable`：验证双列几何和滚动后的末尾学习资料入口可达。新业务入口统一使用已有的有界 `revealTool`，不再假定必吃榜初始就在可视区域。UI 方法仍为 73 项、Swift 单测仍为 500，未新增颜色/缩放常量镜像测试。
