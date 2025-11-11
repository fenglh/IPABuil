# Repository Guidelines

## Project Structure & Module Organization
- `IPABuild/` contains the macOS command-line tool; `main.swift` starts execution, while `Sources/` holds core types such as `IPABuild.swift`, `ExportOptions.swift`, `MobileProvision.swift`, and `ShellOut.swift`.
- Shared helpers live in `Sources/Extension/`, and sample provisioning assets stay under `Resources/` for local validation only.
- Manage CocoaPods through the root `Podfile`; resolved dependencies sit in `Pods/`. Always open `IPABuild.xcworkspace` to ensure the Pods target is linked.
- `X509Certificate/` is a reference library and podspec used for signing experiments; it is optional for mainline builds but useful for understanding certificate parsing.

## Build, Test, and Development Commands
- `arch -x86_64 pod install` (Apple Silicon) or `pod install` (Intel) keeps Pods aligned with `Podfile.lock`.
- `xcodebuild -workspace IPABuild.xcworkspace -scheme IPABuild -configuration Debug build` performs the standard debug build and surfaces compiler regressions early.
- During development you can call `IPABuild().run(scheme: "IPABuild", method: .appStore)` from `main.swift` to wrap `xcodebuild archive` and `-exportArchive` for quick dry runs.
- Launching via Xcode is the easiest way to inspect certificate and provisioning output in the console before modifying export options.

## Coding Style & Naming Conventions
- Target Swift 5 with four-space indentation, early returns, and concise comments reserved for non-obvious flows.
- Types use PascalCase, methods and properties use camelCase, and files should mirror their primary type (e.g., `ExportOptions.swift`).
- Prefer Xcode's built-in formatter; no external linter is enforced, so keep diffs minimal and focused.

## Testing Guidelines
- There is no standalone test target; rely on manual verification.
- Run the tool locally to ensure certificate listings print, then execute an archive dry run and confirm the log contains `ARCHIVE SUCCEEDED`.
- Record the exact commands and key console snippets in PRs so reviewers can reproduce issues.

## Commit & Pull Request Guidelines
- Use short, imperative commits that cover a single concern, such as `build: fix export options for ad-hoc` or `ci: harden archive logging`.
- PRs should state the motivation, summarize changes, link issues, and attach relevant logs or screenshots.
- Always describe the manual validation you performed (commands, expected output) to keep reviewers aligned.

## Security & Configuration Tips
- Never commit real certificates, private keys, or provisioning profiles; keep them in the system keychain and `~/Library/MobileDevice/Provisioning Profiles/` respectively.
- Avoid editing generated `Pods/` sources. Update `Podfile`, rerun `pod install`, and verify the workspace before committing.
