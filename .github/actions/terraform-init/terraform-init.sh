#!/usr/bin/env bash
# DIRS（JSON 配列）のディレクトリごとに terraform init し、init できたディレクトリを出力 initialized に JSON 配列で書く
set -euo pipefail

mkdir -p "${TF_PLUGIN_CACHE_DIR}"
list=$(mktemp)
jq -r '.[]' <<< "${DIRS}" > "${list}"

initialized="${RUNNER_TEMP}/terraform-initialized.txt"
: > "${initialized}"
status=0
while IFS= read -r dir; do
  # 改行を含むパスは terraform-dirs で拒否済みのため、::group:: のタイトルは % だけをエスケープすればよい
  echo "::group::${dir//%/%25}"
  # lock ファイルがあれば読み取り専用で使い、required_providers と合わなければ失敗させる
  args=(-backend=false)
  if [ -f "${dir}/.terraform.lock.hcl" ]; then args+=(-lockfile=readonly); fi

  # init に失敗したディレクトリは validate / test しない（module・provider が未導入なことによる二次的なエラーしか出ない）。
  # lock ファイルに無いハッシュ（多くは linux_amd64 のもの）を readonly のため追記できなかったときは、
  # init は警告だけで成功するが provider を検証できないため失敗とする。
  # terraform（provider・external data source を含む）が stdin を読んでディレクトリ一覧を消費しないよう、< /dev/null で切り離す
  if terraform -chdir="${dir}" init "${args[@]}" < /dev/null 2>&1 | tee "${RUNNER_TEMP}/init.log" \
    && ! grep -q 'Provider lock file not updated' "${RUNNER_TEMP}/init.log"; then
    printf '%s\n' "${dir}" >> "${initialized}"
  else
    status=1
  fi
  echo "::endgroup::"
done < "${list}"
echo "initialized=$(jq -Rsc 'split("\n")[:-1]' "${initialized}")" >> "${GITHUB_OUTPUT}"
exit "${status}"
