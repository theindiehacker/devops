#!/usr/bin/env bash
# 今の Organization の設定を state に取り込む（初回と、state を失くしたときに使う）。
# GitHub の設定は変えない。state に入っているものは飛ばし、GitHub に無いものは取り込まない（apply で作られる）。
#
# 使い方（docs/SETUP.md の「1.」）:
#   terraform -chdir=terraform/github init
#   terraform/github/import.sh
set -euo pipefail

cd "$(dirname "$0")"

owner="theindiehacker"
# local backend の state。無ければ初回（state list は state が無いと失敗する）
state=""
if [ -f terraform.tfstate ]; then
  state=$(terraform state list)
fi

# $1: Terraform のアドレス、$2: import の ID（空なら GitHub に無い）
import() {
  local address=$1 id=$2
  if grep -qxF "${address}" <<< "${state}"; then
    echo "skip: ${address}（state にある）"
  elif [ -z "${id}" ]; then
    echo "skip: ${address}（GitHub に無いため、apply で作られる）"
  else
    terraform import -input=false "${address}" "${id}"
  fi
}

# $1: API のパス。id を出す。404 のときだけ何も出さず、ほかのエラー（認証・scope・5xx）では止める
lookup_id() {
  local out
  if out=$(gh api "$1" --jq .id 2>&1); then
    printf '%s\n' "${out}"
  elif [[ "${out}" != *"HTTP 404"* ]]; then
    printf '%s\n' "${out}" >&2
    return 1
  fi
}

# 引数の中のコマンド置換は失敗しても set -e で止まらないため、いったん変数に入れる
org_id=$(gh api "orgs/${owner}" --jq .id)
import github_organization_settings.this "${org_id}"

team_id=$(lookup_id "orgs/${owner}/teams/security")
import github_team.security "${team_id}"
import github_team_members.security "${team_id}"

for role in security_manager all_repo_write; do
  role_id=$(gh api "orgs/${owner}/organization-roles" --jq ".roles[] | select(.name == \"${role}\") | .id")
  if [ -z "${role_id}" ]; then
    echo "Organization role ${role} が見つかりません" >&2
    exit 1
  fi
  # パイプで grep -q に渡すと、grep が先に終わったときに gh が SIGPIPE で失敗し、pipefail で一致しなかった扱いになる
  teams=$(gh api --paginate "orgs/${owner}/organization-roles/${role_id}/teams" --jq '.[].slug')
  assigned=""
  if grep -qxF security <<< "${teams}"; then
    assigned="${role_id}:security"
  fi
  import "github_organization_role_team.security[\"${role}\"]" "${assigned}"
done

# ルールセットは名前で探す（rulesets.tf の name と同じ）。名前が違うと別のルールセットが作られるため、
# 取り込まなかったルールセットを最後に出す（統合して不要になった旧ルールセットは消す。
# 残すと、その必須ワークフローを消したときに全 repo の PR が止まる）
rulesets=$(gh api --paginate "orgs/${owner}/rulesets" --jq '.[] | [.name, .id] | @tsv')
imported=""
import_ruleset() {
  local address=$1 name=$2
  import "${address}" "$(awk -F '\t' -v name="${name}" '$1 == name { print $2 }' <<< "${rulesets}")"
  imported+="${name}"$'\n'
}
import_ruleset github_organization_ruleset.main_push '🚫 main への直接 push 禁止'
import_ruleset github_organization_ruleset.pull_request_approval '✅ PR の承認を必須化'
import_ruleset github_organization_ruleset.security_scan '🛡️ 脆弱性・IaC 設定ミス検知'
import_ruleset github_organization_ruleset.security_config_review '✔️ セキュリティ設定変更の承認必須化'
import_ruleset github_organization_ruleset.workflow_change_review '🛠️ 検知ワークフロー変更の承認必須化'
import_ruleset github_organization_ruleset.style_check '✏️ スタイルチェック'
import_ruleset github_organization_ruleset.sensitive_files '🚫 機密ファイルの push 禁止'
import_ruleset github_organization_ruleset.release_tags '🔒 リリースタグの変更禁止'

import github_actions_organization_permissions.this "${owner}"
import github_actions_organization_workflow_permissions.this "${owner}"

while IFS=$'\t' read -r name id; do
  if [ -n "${name}" ] && ! grep -qxF "${name}" <<< "${imported}"; then
    echo "Terraform で管理していないルールセット: ${name}（不要なら消す: gh api -X DELETE orgs/${owner}/rulesets/${id}）"
  fi
done <<< "${rulesets}"
