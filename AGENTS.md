# Repository Guidelines

## 项目结构与模块组织
- `IPABuild/` 为 macOS 命令行工具；入口 `main.swift`；核心代码在 `Sources/`（如 `IPABuild.swift`、`ExportOptions.swift`、`MobileProvision.swift`、`ShellOut.swift`）；通用扩展在 `Sources/Extension/`；示例资源在 `Resources/`。
- 依赖通过 CocoaPods 管理（见 `Podfile`），产出在 `Pods/`。构建优先使用 `IPABuild.xcworkspace`。
- `X509Certificate/` 是示例库与 podspec，非主目标必需。

## 构建、测试与开发命令
- 安装依赖（Apple Silicon）：`arch -x86_64 pod install`；其他环境：`pod install`。
- 调试构建：`xcodebuild -workspace IPABuild.xcworkspace -scheme IPABuild -configuration Debug build`。
- 归档导出：由 `IPABuild.swift` 生成并封装 `xcodebuild archive` 与 `-exportArchive`。开发期可在 `main.swift` 调用 `IPABuild().run(scheme: "IPABuild", method: .appStore)`。
- 本地运行：用 Xcode 打开 workspace 运行，控制台会输出证书与描述文件信息。

## 代码风格与命名规范
- Swift 5 / Xcode 14+；4 空格缩进；建议早返回；仅为复杂逻辑添加简短注释。
- 命名：类型用 `PascalCase`，函数/变量用 `camelCase`；文件名与主类型一致（如 `ExportOptions.swift`）。
- 格式化：使用 Xcode 自带格式化；当前未强制使用 linter。

## 测试指南
- 暂无独立测试 target。建议手动验证：
  - 运行程序，检查控制台证书列表输出。
  - 使用已知 scheme 进行归档 dry-run，确认日志包含 "ARCHIVE SUCCEEDED"。
- 在 PR 中附复现命令与关键日志，便于审阅。

## 提交与 Pull Request
- 提交信息简洁、祈使语；一次只改一件事。示例：`build: fix export options for ad-hoc` 或 `+ 优化打包`。
- PR 应包含：变更目的与背景、测试步骤与期望输出、关联 issue、必要截图或日志。

## 安全与配置提示（可选）
- 不要提交真实证书、私钥或描述文件；证书保存在系统钥匙串，描述文件位于 `~/Library/MobileDevice/Provisioning Profiles/`。
- 不要直接修改 `Pods/` 内容；改动应通过 `Podfile` 与 `pod install` 生效。
