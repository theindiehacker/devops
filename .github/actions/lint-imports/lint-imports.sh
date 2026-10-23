#!/usr/bin/env bash
# プロジェクト（カレントディレクトリ）に割り当てられた import-linter の設定を、プロジェクトの環境で検査する
set -euo pipefail

# python-targets が自分に割り当てた設定だけを検査する（設定はプロジェクト直下とは限らない）
configs=$(mktemp)
jq -j --arg project "${PROJECT}" '.[] | select(.project == $project) | .rel, "\u0000"' <<< "${IMPORTLINTERS}" > "${configs}"
if [ ! -s "${configs}" ]; then
  echo "::notice::このプロジェクトに割り当てられた import-linter の設定が無いため skip"
  exit 0
fi
status=0
while IFS= read -r -d '' dir; do
  echo "::group::${dir//$'\n'/%0A}"
  uv run --directory "${dir}" --no-sync --with "import-linter==${IMPORT_LINTER_VERSION}" lint-imports --no-cache --no-logo || status=1
  echo "::endgroup::"
done < "${configs}"
if [ "${status}" -ne 0 ]; then
  echo "::error::lint-imports: 「Could not find package」が出る場合は、pyproject.toml に [build-system] を宣言して自パッケージを導入するか、root_package を実在するパッケージに合わせてください（https://import-linter.readthedocs.io/en/stable/usage.html）"
fi
exit "${status}"
