# iOS CI

工作流位于 `.github/workflows/`，具体触发分支、超时和保留期以配置为准。

- `ios-ci.yml`：构建一次测试产物，按 `.github/ci-test-shards.json` 分组执行 Swift 单元与 UI 测试，并运行 Rust、Python 检查。UI 失败允许一次有界复验，两次结果均保留；依赖复验通过会给出警告。
- `ios-unsigned-ipa.yml`：构建 Release Archive，核验贡献配置、App/Widget、快捷指令元数据、Release 裁剪和嵌套签名声明，生成供重签的 IPA。
- `ios-release-readiness.yml`：检查隐私与打包边界并保存 Archive。
- 设备包使用 `CANTEEN_WRITE_KEY` Secret。配置 `SENTRY_AUTH_TOKEN` 后上传同一 Archive 的 dSYM；令牌不进入 App。

本地检查：

```bash
python3 scripts/check-swift-test-budget.py
python3 scripts/ci-test-shards.py validate
python3 -m unittest discover -s scripts/tests -v
```

Swift 单元测试方法上限 600；UI、Python、Rust 不计入。实际通过数量与失败原因从当前运行的日志及 xcresult 查看，不把历史运行结果当作当前验证。
