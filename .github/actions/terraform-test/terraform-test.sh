#!/usr/bin/env bash
# DIRS（JSON 配列）のうち、テストがあるディレクトリで terraform test を実行する
set -euo pipefail
shopt -s nullglob

list=$(mktemp)
jq -r '.[]' <<< "${DIRS}" > "${list}"

status=0
while IFS= read -r dir; do
  # terraform test はモジュールのディレクトリで実行する。テストはその直下か tests/ に置かれる（terraform の既定）
  tests=("${dir}"/{,tests/}*.tftest.{hcl,json})
  if [ "${#tests[@]}" -eq 0 ]; then continue; fi
  echo "::group::${dir//%/%25}"
  # クラウドの認証情報は渡さないため、command = plan と mock_provider で完結するテストだけが通る
  terraform -chdir="${dir}" test < /dev/null || status=1
  echo "::endgroup::"
done < "${list}"
exit "${status}"
