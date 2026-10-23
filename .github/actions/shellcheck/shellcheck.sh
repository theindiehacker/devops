#!/usr/bin/env bash
# FILES（JSON 配列）のシェルスクリプトを、導入した shellcheck で lint する
set -euo pipefail

archive="${RUNNER_TEMP}/shellcheck-${VERSION}.linux.x86_64.tar.xz"
curl -sSfL -o "${archive}" "https://github.com/koalaman/shellcheck/releases/download/${VERSION}/${archive##*/}"

# SHA-256 検証（改ざん・破損を検知）
echo "${SHA256}  ${archive}" | sha256sum -c -

sudo tar -xJ -C /usr/local/bin -f "${archive}" --strip-components=1 "shellcheck-${VERSION}/shellcheck"
shellcheck --version

# プロセス置換では jq の失敗が伝わらないため、いったんファイルに受ける
list="${RUNNER_TEMP}/shellcheck-targets.txt"
jq -r '.[]' <<< "${FILES}" > "${list}"
mapfile -t targets < "${list}"
# 出力には対象 repo のパスやソースが含まれるため、全行に "| " を付けてワークフローコマンドを防ぐ（runner は行頭の空白を除いて判定するため字下げでは防げない）
shellcheck --severity=warning --external-sources "${targets[@]}" 2>&1 | sed 's/\r/\\r/g; s/^/| /'
