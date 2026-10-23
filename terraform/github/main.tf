# Organization の設定（docs/SETUP.md の「1.」）。手元から apply し、state は手元のファイルに置く（local backend）。
# token は GITHUB_TOKEN が無ければ `gh auth token` を使う（admin:org の scope が要る）
provider "github" {
  owner = local.owner
}

locals {
  owner = "theindiehacker"

  # 今の値を読むだけで、Terraform では管理しない項目の取得元（billing_email など）
  organization = jsondecode(data.github_rest_api.organization.body)

  # Organization role の名前 → ID（security_manager / all_repo_write などの定義済みロールも含む）
  role_ids = { for role in data.github_organization_roles.all.roles : role.name => role.role_id }
}

data "github_rest_api" "organization" {
  endpoint = "orgs/${local.owner}"
}

data "github_organization_roles" "all" {}

# 必須ワークフローの実体と、この repo だけに掛けるルールセットの対象（ルールセットは repo を名前ではなく ID で持つ）
data "github_repository" "github_workflows" {
  full_name = "${local.owner}/github-workflows"
}

# Renovate の更新 PR を承認なしで自動マージするため、「✅ PR の承認を必須化」の bypass に入れる
data "github_app" "renovate" {
  slug = "renovate-${local.owner}"
}

# 二要素認証の必須化は API で変えられないため、UI で設定し、ここでは plan のときに確かめるだけにする
check "two_factor_requirement" {
  assert {
    condition     = local.organization.two_factor_requirement_enabled
    error_message = "二要素認証が必須になっていません。docs/SETUP.md の「0.」の手順で設定してください"
  }
}
