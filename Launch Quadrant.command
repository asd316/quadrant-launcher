#!/bin/zsh
# 双击启动 Quadrant Launcher：先编译，再重启应用并打开面板。
# 每次都重启，避免看到旧版本；状态存在 SQLite 里，不会丢。
set -euo pipefail
cd "${0:A:h}"

BIN=.build/debug/QuadrantApp
pause_on_error() {
  echo
  read -k 1 "?按任意键关闭窗口…"
}

if ! command -v swift >/dev/null 2>&1; then
  echo "找不到 swift。请先安装 Xcode Command Line Tools：xcode-select --install"
  pause_on_error
  exit 1
fi

echo "编译 Quadrant Launcher…"
if ! swift build --product QuadrantApp --disable-sandbox --quiet; then
  echo
  echo "编译失败，上面是错误信息。"
  pause_on_error
  exit 1
fi

if pgrep -x QuadrantApp >/dev/null 2>&1; then
  pkill -x QuadrantApp 2>/dev/null || true
  sleep 0.3
fi

QUADRANT_AUTOOPEN=1 nohup "$BIN" >/tmp/quadrant-launcher.log 2>&1 &
disown
echo "已启动，面板马上打开；菜单栏会出现 ▦ 图标。"

sleep 1
