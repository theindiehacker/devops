#!/usr/bin/env bash
# PostToolUse (Edit|Write) フック: 編集のたびに自動整形 + 静的検査を回す。
#
# 移植元では settings.json に直書きの `task style:fix` / `task style:check` だったが、
# プラグインとして全社配布するにあたり「task 未導入のリポジトリ / style タスクを持たない
# リポジトリでは何もしない」防御的ラッパーにしている (毎編集でエラーを撒かないため)。
# style:check の失敗は exit 2 + stderr で Claude にフィードバックし、その場で直させる。

set -uo pipefail

command -v task >/dev/null 2>&1 || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
[ -f Taskfile.yml ] || [ -f Taskfile.yaml ] || exit 0

# ここに来た時点で Taskfile は存在する。それでも --list-all が失敗する場合、直前の編集で壊した
# 可能性もあるが、元から解決できない includes を持つリポジトリも珍しくない。後者で全編集を
# ブロックすると作業不能になるので、非ブロッキング (exit 0) で警告だけ出して抜ける。
if ! tasks=$(task --list-all 2>&1); then
  printf '%s\n' "task --list-all が失敗したため style タスクをスキップします (Taskfile を確認してください):" "$tasks" >&2
  exit 0
fi

run_if_defined() {  # $1=タスク名  失敗したら出力を stderr へ流して非ゼロを返す
  local name="$1" out
  # --list-all は "* name: 説明" 形式。前方一致で style:fix:frontend のような別タスクを
  # 拾わないよう、名前の直後はコロン+空白か行末に限定する。
  echo "$tasks" | grep -qE "^\* ${name}(:[[:space:]]|[[:space:]]|$)" || return 0
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
