#!/usr/bin/env bash
# DIRS（JSON 配列）の各ディレクトリで RUN を実行する。1 つ失敗しても残りは続け、最後に 1 を返す
set -euo pipefail

# プロセス置換では jq の失敗が伝わらないため、いったんファイルに受ける
list=$(mktemp)
jq -r '.[]' <<< "${DIRS}" > "${list}"

status=0
while IFS= read -r dir; do
  # 対象 repo 由来のパスで ::group:: の行を分けられないようエスケープする
  echo "::group::${dir//%/%25}"
  # コマンド（terraform の provider・external data source など）が stdin を読んでディレクトリ一覧を消費しないよう、< /dev/null で切り離す
  (cd "${dir}" && bash -c "${RUN}") < /dev/null || status=1
  echo "::endgroup::"
done < "${list}"
exit "${status}"
