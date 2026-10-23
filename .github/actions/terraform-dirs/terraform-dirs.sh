#!/usr/bin/env bash
# git 管理下の *.tf / *.tf.json があるディレクトリを、出力 dirs に JSON 配列で書く。
# .terraform はキャッシュ・vendored モジュール置き場のため対象外
set -euo pipefail

# ディレクトリは 1 行 1 つで扱うため、改行を含むパスは拒否する
list="${RUNNER_TEMP}/terraform-dirs.txt"
git ls-files -z -- ':(glob)**/*.tf' ':(glob)**/*.tf.json' \
  | while IFS= read -r -d '' f; do
      if [[ "${f}" == *[$'\n\r']* ]]; then echo "::error::改行を含むパスは検査できません" >&2; exit 1; fi
      if [[ "${f}" == */* ]]; then printf '%s\n' "${f%/*}"; else echo .; fi
    done \
  | { grep -Ev '(^|/)\.terraform(/|$)' || true; } \
  | sort -u > "${list}"
# パスは対象 repo 由来のため、行頭に出してワークフローコマンドとして解釈されないよう "- " を付ける
sed 's/^/- /' "${list}"
echo "dirs=$(jq -Rsc 'split("\n")[:-1]' "${list}")" >> "${GITHUB_OUTPUT}"
