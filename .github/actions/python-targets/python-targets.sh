#!/usr/bin/env bash
# uv.lock のあるディレクトリ（プロジェクト）を列挙し、pyproject.toml と import-linter の設定を担当プロジェクトに割り当てる。
# 「どのディレクトリがどの uv.lock に属するか」の判定はここに一本化する
# （各 job で同じ探索を書くと、片方だけ直したときに規約の判定と検査範囲が食い違う）
set -euo pipefail

# プロセス置換では git の失敗が伝わらないため、pipefail の効くパイプラインで受ける（該当なしは [] になる）。
# -z のまま渡す（改行や非 ASCII を含むパスが壊れるため）
json=$(git ls-files -z -- ':(glob)**/uv.lock' | jq -Rsc 'split("\u0000")[:-1] | map(sub("/?uv\\.lock$"; "") | if . == "" then "." else . end)')
echo "projects=${json}" >> "${GITHUB_OUTPUT}"
json=$(jq -c '. as $all | map(. as $p | {key: $p, value: [$all[] | select(. != $p) | if $p == "." then . elif startswith($p + "/") then ltrimstr($p + "/") else empty end]}) | from_entries' <<< "${json}")
echo "nested=${json}" >> "${GITHUB_OUTPUT}"

# 最も近い祖先の uv.lock のディレクトリ。どこにも無ければ空
owner() {
  local dir=$1
  while [ ! -e "${dir}/uv.lock" ] && [ "${dir}" != . ]; do dir=$(dirname "${dir}"); done
  if [ -e "${dir}/uv.lock" ]; then printf '%s' "${dir}"; fi
}
assign() {
  local path dir project rel
  while IFS= read -r -d '' path; do
    dir=$(dirname "${path}")
    project=$(owner "${dir}")
    if [ "${dir}" = "${project}" ]; then rel=.; else rel=${dir#"${project}/"}; fi
    jq -nc --arg path "${path}" --arg project "${project}" --arg rel "${rel}" '$ARGS.named'
  done < "$1" | jq -sc .
}

# git grep は該当なしで 1 を返すため、それ以外の失敗だけを止める
files=$(mktemp)
git grep -lzE '^\[(project|tool\.poetry|tool\.uv\.workspace)\]' -- ':(glob)**/pyproject.toml' > "${files}" || [ "$?" -eq 1 ]
json=$(assign "${files}")
echo "pyprojects=${json}" >> "${GITHUB_OUTPUT}"

git grep -lzE '^\[(tool\.)?importlinter\]' -- ':(glob)**/pyproject.toml' ':(glob)**/setup.cfg' ':(glob)**/.importlinter' > "${files}" || [ "$?" -eq 1 ]
json=$(assign "${files}")
echo "importlinters=${json}" >> "${GITHUB_OUTPUT}"
