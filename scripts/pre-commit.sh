#!/usr/bin/env bash
#
# pre-commit hook for camera_handheld
#
# Enforces, before every commit:
#   flutter analyze --no-fatal-infos   (must be "No issues found!")
#   flutter test                       (must pass)
#
# Install (from repo root):
#   ln -s ../../scripts/pre-commit.sh .git/hooks/pre-commit
#
# Emergency bypass (not recommended): git commit --no-verify
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! command -v flutter >/dev/null 2>&1; then
  echo "pre-commit: 'flutter' not found on PATH; cannot verify. Use 'git commit --no-verify' to bypass." >&2
  exit 1
fi

echo "==> flutter analyze --no-fatal-infos"
flutter analyze --no-fatal-infos

echo "==> flutter test"
flutter test

echo "==> analyze + test: PASSED"
