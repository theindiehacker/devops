#!/usr/bin/env bash
# プロジェクト（カレントディレクトリ）の uv workspace のメンバーごとに deptry を実行する
set -euo pipefail

# uv workspace は、依存を宣言する単位であるメンバーごとに検査する（[project] を持たない virtual root は列挙されない）
workspace=$(uv workspace list --paths)
if [ -z "${workspace}" ]; then
  echo "::notice::workspace にメンバーが無いため skip"
  exit 0
fi
status=0
while IFS= read -r member; do
  # workspace ルートの deptry . は配下メンバーのソースまで走査するため、他のメンバーを除外する
  args=()
  while IFS= read -r other; do
    case "${other}" in "${member}"/*) args+=(--extend-exclude "^${other#"${member}/"}/") ;; esac
  done <<< "${workspace}"
  echo "::group::${member}"
  uv run --directory "${member}" --no-sync --with "deptry==${DEPTRY_VERSION}" deptry . "${args[@]}" || status=1
  echo "::endgroup::"
done <<< "${workspace}"
if [ "${status}" -ne 0 ]; then
  echo "::error::deptry: 自プロジェクトのパッケージ（src/ や app/ 配下など）が DEP001 / DEP003 になる場合は pyproject.toml の [tool.deptry] known_first_party に（https://deptry.com/usage/#known-first-party）、別の uv.lock を持つ入れ子のプロジェクトなど検査から外すディレクトリは extend_exclude に（https://deptry.com/usage/#extend-exclude）追加してください。その他の違反の対処は https://deptry.com/rules-violations/ を参照してください"
fi
exit "${status}"
