# Organization の基本設定。
# ベース権限・リポジトリ作成・fork の 3 つだけを管理し、ほかの項目は今の値をそのまま渡す
# （provider は billing_email を必須とし、未指定の項目を既定値で上書きするため）
resource "github_organization_settings" "this" {
  # 組織のリポジトリに対するベース権限。
  # 将来メンバーが増える前提で「職務分掌」を意識したい → none、
  # 「組織メンバー＝基本的に全部のコードは見えてよい」という文化 & まだ少人数 → read
  default_repository_permission = "read"

  # 意図しない公開リポジトリの作成を防ぐため、管理者しかリポジトリを作成できないようにする
  members_can_create_repositories         = false
  members_can_create_public_repositories  = false
  members_can_create_private_repositories = false

  # 組織のリポジトリを fork できないようにする
  members_can_fork_private_repositories = false

  # ここから下は管理しない（今の値をそのまま渡す）
  billing_email    = local.organization.billing_email
  name             = local.organization.name
  description      = local.organization.description
  company          = local.organization.company
  blog             = local.organization.blog
  email            = local.organization.email
  location         = local.organization.location
  twitter_username = local.organization.twitter_username

  has_organization_projects                                    = lookup(local.organization, "has_organization_projects", null)
  has_repository_projects                                      = lookup(local.organization, "has_repository_projects", null)
  members_can_create_pages                                     = lookup(local.organization, "members_can_create_pages", null)
  members_can_create_public_pages                              = lookup(local.organization, "members_can_create_public_pages", null)
  members_can_create_private_pages                             = lookup(local.organization, "members_can_create_private_pages", null)
  web_commit_signoff_required                                  = lookup(local.organization, "web_commit_signoff_required", null)
  advanced_security_enabled_for_new_repositories               = lookup(local.organization, "advanced_security_enabled_for_new_repositories", null)
  dependabot_alerts_enabled_for_new_repositories               = lookup(local.organization, "dependabot_alerts_enabled_for_new_repositories", null)
  dependabot_security_updates_enabled_for_new_repositories     = lookup(local.organization, "dependabot_security_updates_enabled_for_new_repositories", null)
  dependency_graph_enabled_for_new_repositories                = lookup(local.organization, "dependency_graph_enabled_for_new_repositories", null)
  secret_scanning_enabled_for_new_repositories                 = lookup(local.organization, "secret_scanning_enabled_for_new_repositories", null)
  secret_scanning_push_protection_enabled_for_new_repositories = lookup(local.organization, "secret_scanning_push_protection_enabled_for_new_repositories", null)

  lifecycle {
    # destroy すると billing_email が email@example.com に、各項目が既定値に戻る
    prevent_destroy = true
  }
}
