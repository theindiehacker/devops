#!/usr/bin/env bash
# actionlint を導入し、GitHub Actions のワークフロー定義を構文チェックする
set -euo pipefail

archive="${RUNNER_TEMP}/actionlint_${VERSION#v}_linux_amd64.tar.gz"
curl -sSfL -o "${archive}" "https://github.com/rhysd/actionlint/releases/download/${VERSION}/${archive##*/}"

# SHA-256 検証（改ざん・破損を検知）
echo "${SHA256}  ${archive}" | sha256sum -c -

sudo tar -xz -C /usr/local/bin -f "${archive}" actionlint
actionlint --version

# workflow command 形式で出力し、検出箇所を PR に annotation 表示する
# shellcheck disable=SC2016 # $err は actionlint のテンプレートの変数
actionlint -format $'{{range $err := .}}::error file={{$err.Filepath}},line={{$err.Line}},col={{$err.Column}}::{{$err.Message}}\n{{end}}'
