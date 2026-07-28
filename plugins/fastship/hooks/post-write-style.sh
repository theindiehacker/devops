#!/usr/bin/env bash
# PostToolUse (Edit|Write) フック: 編集のたびに自動整形 + 静的検査を回す。
#
# fastship.jp では settings.json に直書きの `task style:fix` / `task style:check` だったが、
# プラグインとして全社配布するにあたり「task 未導入のリポジトリ / style タスクを持たない
# リポジトリでは何もしない」防御的ラッパーにしている (毎編集でエラーを撒かないため)。
# style:check の失敗は exit 2 + stderr で Claude にフィードバックし、その場で直させる。

set -uo pipefail

command -v task >/dev/null 2>&1 || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[ -f Taskfile.yml ] || [ -f Taskfile.yaml ] || exit 0

tasks=$(task --list-all 2>/dev/null || true)

run_if_defined() {  # $1=タスク名  失敗したら出力を stderr へ流して非ゼロを返す
  local name="$1" out
  echo "$tasks" | grep -qE "^\* ${name}(:|\s|$)" || return 0
  if ! out=$(task "$name" 2>&1); then
    printf '%s\n' "task ${name} が失敗しました:" "$out" >&2
    return 1
  fi
  return 0
}

rc=0
run_if_defined style:fix || rc=2
run_if_defined style:check || rc=2
exit "$rc"
