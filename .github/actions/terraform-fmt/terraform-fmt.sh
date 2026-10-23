#!/usr/bin/env bash
# FILES（JSON 配列）のあるディレクトリを terraform fmt -check で検査する
set -euo pipefail

# 対象 repo 由来のパスで ::group:: の行を分けられないようエスケープする
escape() { local value=${1//%/%25}; value=${value//$'\r'/%0D}; printf '%s' "${value//$'\n'/%0A}"; }

# fmt は -recursive を付けなければ指定ディレクトリ直下だけを見るため、変更ファイルを
# ディレクトリに集約する。repo 全体を -recursive で検査すると、その PR が触っていない
# ディレクトリに元からある崩れでも fail してしまう。
# .terraform はキャッシュ・vendored モジュール置き場のため検査対象外
dirs=$(
  jq -r '.[]' <<< "${FILES}" | { grep -Ev '(^|/)\.terraform/' || true; } \
  | while IFS= read -r f; do dirname "${f}"; done | sort -u
)

status=0
while IFS= read -r dir; do
  if [ -z "${dir}" ]; then continue; fi
  echo "::group::$(escape "${dir}")"
  # 結果は annotation にせず log に出す（書式が一致しないファイルと差分を出し、どう直すかを読めるようにする）
  # 差分の文脈行は PR のファイルの内容そのままなので、行頭に "│ " を付けてワークフローコマンドとして解釈されないようにする
  terraform fmt -check -no-color -diff "${dir}" | sed 's/^/│ /' || status=1
  echo "::endgroup::"
done <<< "${dirs}"
exit "${status}"
