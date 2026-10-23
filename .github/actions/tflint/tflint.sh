#!/usr/bin/env bash
# CONFIG の設定で、FILES（JSON 配列）のあるディレクトリを tflint で lint する
set -euo pipefail

# git grep ではなく grep -R で作業ツリーを読む（git grep は symlink のリンク先を読まず、-I を付けると
# NUL バイト入りの .tf も読み飛ばすが、tflint はどちらも読み込んで ignore が効くため）。
# 終了コード 2（読めないファイルあり）はマッチがあっても返るため、1（マッチなし）以外はすべて失敗にする。
# grep はパスをエスケープせず改行（CR を含む）入りのパスで行が分かれるため、CR を可視化し stderr も含め
# 全行に "- " を付けてワークフローコマンドとして解釈されないようにする
rc=0
grep -RlF -D skip --include='*.tf' --exclude-dir=.git 'tflint-ignore' . > "${RUNNER_TEMP}/tflint-ignore.txt" 2>&1 || rc=$?
sed 's/\r/\\r/g; s/^/- /' "${RUNNER_TEMP}/tflint-ignore.txt"
if [ "${rc}" -ne 1 ]; then
  echo "::error::tflint-ignore コメントがあるか、読み込めない .tf があります（ルールは github-workflows の .github/workflows/style.yml で全リポジトリ共通に固定しています）"
  exit 1
fi

# 以降の tflint はすべてこの設定と plugin を使う（対象 repo の .tflint.hcl や、
# cwd の ./.tflint.d/plugins が優先されて設定・plugin を差し替えられないよう固定する）
export TFLINT_CONFIG_FILE="${RUNNER_TEMP}/.tflint.hcl"
export TFLINT_PLUGIN_DIR="${RUNNER_TEMP}/tflint-plugins"
printf '%s' "${CONFIG}" > "${TFLINT_CONFIG_FILE}"

# トークンは plugin の取得にだけ使い、PR のコードを読む lint には渡さない
GITHUB_TOKEN="${INIT_TOKEN}" tflint --init
unset INIT_TOKEN

# lint はディレクトリ（モジュール）単位のため、変更ファイルをディレクトリに集約する。
# .terraform はキャッシュ・vendored モジュール置き場のため lint 対象外
dirs="${RUNNER_TEMP}/tflint-dirs.txt"
jq -r '.[] | select(test("(^|/)\\.terraform/") | not) | if contains("/") then sub("/[^/]*$"; "") else "." end' \
  <<< "${FILES}" | sort -u > "${dirs}"

# 対象 repo 由来のパスで ::group:: の行を分けられないようエスケープする。
# 結果は annotation にせず log に出す（既定の形式で、ファイル・行・ルール名と該当箇所が出る）。
# 出力には対象 repo のパスやソースが含まれるため、全行に "| " を付けてワークフローコマンドを防ぐ（runner は行頭の空白を除いて判定するため字下げでは防げない）
escape() { local value=${1//%/%25}; value=${value//$'\r'/%0D}; printf '%s' "${value//$'\n'/%0A}"; }
status=0
while IFS= read -r dir; do
  echo "::group::$(escape "${dir}")"
  tflint --chdir="${dir}" 2>&1 | sed 's/\r/\\r/g; s/^/| /' || status=1
  echo "::endgroup::"
done < "${dirs}"
exit "${status}"
