# GitHub Actions のセキュリティ設定（Organization → Settings → Actions → General）

# 実行できる action を、Organization のものと GitHub 製と下の許可リストに限る。
# 各リポジトリが新しい外部 action を使う場合はこのリストへの追加が必要（SHA ピン留めは各ワークフロー側で行う）
resource "github_actions_organization_permissions" "this" {
  enabled_repositories = "all"
  allowed_actions      = "selected"

  allowed_actions_config {
    github_owned_allowed = true
    verified_allowed     = false
    patterns_allowed = [
      "anthropics/claude-code-action@*",
      "aquasecurity/trivy-action@*",
      # aquasecurity/trivy-action が内部で使用する
      "aquasecurity/setup-trivy@*",
      # python（style.yml）が使用する
      "astral-sh/ruff-action@*",
      "astral-sh/setup-uv@*",
      "docker/setup-buildx-action@*",
      "docker/build-push-action@*",
      "dorny/paths-filter@*",
      # Workload Identity 連携で Google Cloud に認証する公式 action（各リポジトリの Terraform plan / apply が使用する）
      "google-github-actions/auth@*",
      "google-github-actions/setup-gcloud@*",
      # terraform / lint（style.yml）が使用する
      "hashicorp/setup-terraform@*",
      # app.fastship.jp の CI（py-check.yml / py-test.yml）が、mise.toml・mise.lock の版で task・uv などを入れるために使用する
      # （組織の必須ワークフローが効かない個人ユーザーのリポジトリでも CI を動かすため）
      "jdx/mise-action@*",
      # anthropics/claude-code-action が内部で使用する
      "oven-sh/setup-bun@*",
      # bundle-size-measure（style.yml）が、フロントエンドのバンドルサイズの増減を PR にコメントするために使用する
      "preactjs/compressed-size-action@*",
      "pypa/gh-action-pypi-publish@*",
      "renovatebot/github-action@*",
      # lint（style.yml）が使用する
      "terraform-linters/setup-tflint@*",
    ]
  }

  lifecycle {
    # destroy すると、すべての action を実行できる設定に戻る
    prevent_destroy = true
  }
}

# GITHUB_TOKEN のデフォルト権限。permissions: を明示しているワークフロー（この repo のものを含む）には影響しない
resource "github_actions_organization_workflow_permissions" "this" {
  organization_slug            = local.owner
  default_workflow_permissions = "read"
  # GITHUB_TOKEN による自己承認で、承認を必須にするルールセットが迂回されるのを防ぐ
  can_approve_pull_request_reviews = false

  lifecycle {
    prevent_destroy = true
  }
}
