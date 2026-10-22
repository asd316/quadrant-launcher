# Raycast · Toggle Quadrant Launcher

把 `Toggle Quadrant Launcher.sh` 挂到 Raycast 的 Script Commands，然后把快捷键设成 `⌃D`。

## Setup

1. 先把 `Quadrant Launcher.app` 放进 `/Applications`，打开一次，让 LaunchServices 注册 URL scheme。
2. 打开 Raycast → **Extensions** → **Script Commands** → **Add Script Directory**。
3. 选择本目录：`<repo>/Scripts/Raycast`。
4. 在 Raycast 里搜索 **Toggle Quadrant Launcher**，打开它的 **Configure**，把 **Hotkey** 设为 `⌃D`。

脚本实际执行：

```bash
open -b com.quadrantlauncher.app "quadrant-launcher://toggle"
```

- app 未运行：启动并打开面板；
- app 已运行、面板关着：打开；
- app 已运行、面板开着：关闭。

## Why not the app's own hotkey?

当前构建没有接 KeyboardShortcuts（需要完整 Xcode）。Raycast 的 Script Command 就是外部快捷键入口，和菜单栏按钮共存。

## Double-click

在 Finder 里双击 `Quadrant Launcher.app`：

- 未运行：启动并打开面板；
- 已运行：把面板带到最前（不会关闭）。

## Troubleshooting

- 快捷键没反应：先在 Raycast 里手动运行一次 Script Command，确认 app 已装进 `/Applications`。
- 如果有多份 app（DMG 里一份、Applications 里一份），先退出并卸载 DMG，只保留 `/Applications` 里的那份。
- URL scheme 检查：`open "quadrant-launcher://toggle"` 应该等价于同一个开关。
