#!/bin/zsh
# 双击启动 Quadrant Launcher：需要时先编译，然后打开面板。
# 已在运行时不会重启，只把面板唤到最前。
set -euo pipefail
cd "${0:A:h}"

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
  pkill -USR1 -x QuadrantApp 2>/dev/null || true
  echo "Quadrant Launcher 已在运行，面板已唤起。"
else
  QUADRANT_AUTOOPEN=1 nohup .build/debug/QuadrantApp >/tmp/quadrant-launcher.log 2>&1 &
  disown
  echo "已启动，面板马上打开；菜单栏会出现 ▦ 图标。"
fi

sleep 1
