#!/usr/bin/env bash
# 変更ファイル一覧を返す（/conform スキルのステップ1が使う）。
#   引数 $1 に diff 範囲（例: main...HEAD）を渡せばそのブランチ diff を対象にする。
#   省略時は未コミット変更（staged + unstaged + 新規追跡ファイル）を漏れなく対象にする。
# 出力は変更ファイルのパスを 1 行ずつ（重複排除・ソート済み）。
set -euo pipefail

RANGE="${1:-}"
if [ -n "$RANGE" ]; then
  git diff --name-only "$RANGE"
else
  { git diff --name-only; git diff --name-only --cached; git ls-files --others --exclude-standard; } | sort -u
fi
