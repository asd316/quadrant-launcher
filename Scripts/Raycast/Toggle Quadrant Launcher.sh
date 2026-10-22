#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Toggle Quadrant Launcher
# @raycast.mode silent
# @raycast.packageName Quadrant Launcher
# @raycast.icon ▦
# @raycast.description Open or close the Quadrant Launcher panel.

open -b com.quadrantlauncher.app "quadrant-launcher://toggle" 2>/dev/null \
  || open -a "Quadrant Launcher" "quadrant-launcher://toggle"
