# Quadrant Launcher

macOS 菜单栏文件启动器：唤起后全屏四象限，快速找到文件并复制路径、拖进别的应用、打开。原生 Swift 6，SwiftPM，macOS 15+，不上架。

## Source of truth

设计在 `docs/`，代码跟着设计走。阅读顺序和目录说明见 `docs/README.md`。

- 写任何功能前，读它对应的规则：业务规则在 `docs/01-product-definition/Domain-Model（业务对象、角色与规则）.md`（R1–R7），交互在 `docs/02-ux-design/`，分层、表结构、接口在 `docs/03-tech-design/`。
- 术语以 `docs/00-project-context/Glossary（术语表）.md` 为准，代码命名用它的英文名（Branch、Star、Lens、Stash、Pinned Slot、Floating Slot、Drill Path）。
- 实现时发现设计不对：先改 `docs/` 里对应的文档，再改代码。文档和代码讲同一件事时，两边同时改。

## Layers

依赖方向固定为 **UI → Core ← System**，由 `Package.swift` 的 target 依赖强制。

| Target | 放什么 |
|---|---|
| `QuadrantCore` | R1–R7 全部规则。同步纯函数：输入数据，输出数据。只 import Foundation。共享类型和端口协议在 `Sources/QuadrantCore/Model.swift`。 |
| `QuadrantSystem` | 实现 Core 的端口：文件扫描、FSEvents、SQLite（GRDB）、配置文件、剪贴板、打开文件。对用户磁盘只读（R6.4）。 |
| `QuadrantUI` | SwiftUI 视图和 AppKit 面板、拖放。只画 Core 给的结果，排序和取舍全在 Core。 |
| `QuadrantApp` | 组装和生命周期。 |
| `PanelSpike` | 验证用的一次性试验（Architecture › Validation），不进产品。 |

Core 的形状：`reduce(状态, 意图, 时间) → (新状态, 副作用)` 和 `project(...) → 每个象限的显示结果`。Core 返回副作用，App 执行。

## Concurrency

Swift 6 语言模式，严格并发检查。

1. 并发代码只放在 System 的文件扫描和监听里。Core 同步；UI 和 App 在 `@MainActor`。
2. 遇到 Sendable 报错，改数据的形状：用值类型、actor，或把工作移回主线程。`@unchecked Sendable` 和 `nonisolated(unsafe)` 只在同一行写明理由时才允许，`Scripts/check-escape-hatches.sh` 会拦下没写理由的。
3. 改了并发相关代码，先跑这个脚本，再说完成。

## Commands

| 做什么 | 命令 |
|---|---|
| 编译 | `swift build` |
| 测试 | `Scripts/test.sh`（参数原样传给 `swift test`，例如 `--filter Reducer`） |
| 并发逃生口检查 | `Scripts/check-escape-hatches.sh` |
| 双击启动面板 | `Launch Quadrant.command`（编译后重启应用，确保看到新版本） |
| 打包 DMG | `Scripts/package-dmg.sh [版本]`（release 构建 + ad-hoc 签名，输出 `dist/Quadrant Launcher <版本>.dmg`） |

多个 agent 同时编译时，各自加 `--scratch-path .build-<名字>`，避免抢同一个 `.build` 锁。如果测试进程以 signal 11 崩溃、而代码看不出问题，多半是共享的 `.build` 里留下了新旧混杂的产物：先跑 `swift package clean` 再测。

## Toolchain

本机目前只有 Command Line Tools，没有完整 Xcode：

- `swift test` 找不到 Testing.framework，所以测试一律走 `Scripts/test.sh`，它会补上框架路径。
- 测试用 swift-testing（`import Testing`），XCTest 在这里不可用。
- KeyboardShortcuts（Architecture 选定的唤起快捷键库）用到 `#Preview` 宏，只有完整 Xcode 能编译，所以暂时不在 `Package.swift` 里。装好 Xcode、组装 App 时再加回来。
- 打包 `.app` 和 DMG 可以用 `Scripts/package-dmg.sh`，做 ad-hoc 签名；Developer ID 签名、公证和上架仍需要完整 Xcode。

## Tests

- 每条业务规则至少一个测试，测试名带规则编号，例如 `r4_1_stashEvictsOldest`。
- Core 用纯数据测：给定状态和意图，检查新状态和副作用。
- System 用临时目录和临时数据库测，测完删除。
- 测试数据参考 `docs/02-ux-design/assets/Prototype-Brief（原型交接说明）.md` 的测试数据集。

## Done

一项工作完成的标准：`swift build` 通过，`Scripts/test.sh` 全部通过，`Scripts/check-escape-hatches.sh` 通过，它对应的规则编号都有测试。
