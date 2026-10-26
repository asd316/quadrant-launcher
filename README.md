# Quadrant Launcher

macOS 菜单栏文件启动器。唤起后全屏显示四个象限，每个象限对应一个常驻文件夹。用它快速找到文件，然后复制路径、拖进别的应用，或直接打开。

原生 Swift 6 + SwiftPM，需要 macOS 15 及以上。

## Build and run

| 做什么 | 命令 |
|---|---|
| 编译 | `swift build` |
| 测试 | `Scripts/test.sh` |
| 编译并打开面板 | 双击 `Launch Quadrant.command` |
| 打包 DMG | `Scripts/package-dmg.sh [版本]`，输出到 `dist/` |
| 全局快捷键 | 用 Raycast Script Command，见 `Scripts/Raycast/README.md` |

只装了 Command Line Tools、没有完整 Xcode 时，`swift test` 找不到 Testing.framework，请用 `Scripts/test.sh`。

## Layout

| 路径 | 内容 |
|---|---|
| `Sources/QuadrantCore` | 业务规则，纯函数，只依赖 Foundation |
| `Sources/QuadrantSystem` | 文件扫描、FSEvents、SQLite、配置、剪贴板 |
| `Sources/QuadrantUI` | SwiftUI 视图和 AppKit 面板 |
| `Sources/QuadrantApp` | 组装和生命周期 |
| `Tests/` | 各层的测试（swift-testing） |
| `docs/` | 设计文档：产品定义、体验设计、技术设计，见 `docs/README.md` |

开发约定见 `AGENTS.md`。
