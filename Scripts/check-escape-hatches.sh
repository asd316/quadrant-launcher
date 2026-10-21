#!/bin/zsh
# Fails when Swift concurrency escape hatches appear without a justification
# comment on the same line (Architecture › Concurrency rules).
cd "${0:A:h}/.."
hits=$(grep -rnE '@unchecked Sendable|nonisolated\(unsafe\)' Sources Tests --include='*.swift' | grep -v '//')
if [[ -n "$hits" ]]; then
  print -u2 "Escape hatch without justification comment:"
  print -u2 "$hits"
  exit 1
fi
