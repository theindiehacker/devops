locals {
  # security チームのメンバー（GitHub のユーザー名 → チームでの役割）
  security_members = {
    gtaiyou24 = "maintainer"
  }

  # 承認者本人が作成した PR は自己承認できない。承認者が 1 人だけの間は、
  # 承認を必須にするルールセットの bypass に Organization の管理者を入れてマージできるようにする
  single_approver = length(local.security_members) == 1
}

# Gitleaks や Trivy などがセキュリティ検知をした時に対応するチーム。
# セキュリティの設定・検知ワークフローを変える PR は、このチームの承認がないとマージできない（rulesets.tf）
resource "github_team" "security" {
  name        = "security"
  description = "🛡️ セキュリティチーム"
  privacy     = "closed"
}

resource "github_team_members" "security" {
  team_id = github_team.security.id

  dynamic "members" {
    for_each = local.security_members
    content {
      username = members.key
      role     = members.value
    }
  }
}

# - security_manager: 全リポジトリの Read 権限が自動付与され、ルールセットの Required reviewers が
#   リポジトリごとのチーム登録（Add teams）なしで自動レビュアー指定されるようになる（新規リポジトリも自動で対象）。
#   org 全体のセキュリティアラートの閲覧・管理権限も付く
# - all_repo_write: 承認が Required approvals にカウントされるのは write アクセス保持者のレビューのみのため、
#   Read 相当の security_manager と併用する（all_repo_write だけでは、承認はできるがレビュアーの自動指定はされない）
resource "github_organization_role_team" "security" {
  for_each = toset(["security_manager", "all_repo_write"])

  role_id   = local.role_ids[each.key]
  team_slug = github_team.security.slug
}
