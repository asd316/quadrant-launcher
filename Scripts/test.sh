#!/bin/zsh
# Runs `swift test`. With only Command Line Tools active, swift-testing's
# Testing.framework is not on the default search path, so add it.
set -e
cd "${0:A:h}/.."
flags=()
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
  F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  flags=(-Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L)
fi
swift test $flags "$@"
