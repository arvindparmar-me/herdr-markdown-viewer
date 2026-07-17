#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
status=0
for t in test_*.sh; do
  printf '\n== %s ==\n' "$t"
  bash "$t" || status=1
done
exit "$status"
