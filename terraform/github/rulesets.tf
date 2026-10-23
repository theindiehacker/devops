# Organization のルールセット。
# branch ruleset が保護するのは default branch のみ。リリースも default branch（main）のマージ済みコミットから行う運用を前提とする。
# タグやリリースブランチを起点にデプロイする運用を導入する場合は、レビューを経ないコミットからタグを切れてしまうため、
# 別途 tag ruleset / 対象ブランチの追加が必要。
#
# 必須ワークフローのルールセット（security_scan / style_check）の bypass には何も入れないこと
# （入れると、失敗した検査を無視してマージできるようになる）。

locals {
  all_merge_methods = ["merge", "squash", "rebase"]

  # Renovate の更新 PR を承認なしで自動マージするため、承認系のルールセットの bypass に入れる（PR のときだけ）
  renovate_app_id = tonumber(data.github_app.renovate.id)

  # 必須ワークフローの実体（この repo の main）。変更には security チームの承認が要る（workflow_change_review）
  required_workflow_repository_id = data.github_repository.github_workflows.repo_id
}

resource "github_organization_ruleset" "main_push" {
  name        = "🚫 main への直接 push 禁止"
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      allowed_merge_methods = local.all_merge_methods
    }
  }
}

# 全 PR に人間のレビュー承認（1 名以上）がないとマージできないようにする。
# 承認が Required approvals にカウントされるのは write アクセス保持者のレビューのみ。PR 作成者本人による自己承認はできない
resource "github_organization_ruleset" "pull_request_approval" {
  name        = "✅ PR の承認を必須化"
  target      = "branch"
  enforcement = "active"

  bypass_actors {
    actor_type  = "Integration"
    actor_id    = local.renovate_app_id
    bypass_mode = "pull_request"
  }

  dynamic "bypass_actors" {
    for_each = local.single_approver ? [true] : []
    content {
      actor_type  = "OrganizationAdmin"
      bypass_mode = "always"
    }
  }

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    pull_request {
      required_approving_review_count = 1
      # 承認後に push されたコミットが再レビューなしでマージされるのを防ぐ
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = false
      allowed_merge_methods             = local.all_merge_methods
    }
  }
}

# シークレット・GitHub Actions の設定・アプリケーションコード・依存パッケージと IaC・イメージの検査（security.yml）
resource "github_organization_ruleset" "security_scan" {
  name        = "🛡️ 脆弱性・IaC 設定ミス検知"
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    required_workflows {
      do_not_enforce_on_create = true

      required_workflow {
        repository_id = local.required_workflow_repository_id
        path          = ".github/workflows/security.yml"
        ref           = "refs/heads/main"
      }
    }
  }
}

# セキュリティ検知の設定ファイル（.gitleaksignore / .trivyignore など）を変更する PR に、security チームの承認を必須にする
resource "github_organization_ruleset" "security_config_review" {
  name        = "✔️ セキュリティ設定変更の承認必須化"
  target      = "branch"
  enforcement = "active"

  dynamic "bypass_actors" {
    for_each = local.single_approver ? [true] : []
    content {
      actor_type  = "OrganizationAdmin"
      bypass_mode = "always"
    }
  }

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    pull_request {
      # 承認の必須化は required_reviewers で行う
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = false
      allowed_merge_methods             = local.all_merge_methods

      required_reviewers {
        reviewer {
          id   = tonumber(github_team.security.id)
          type = "Team"
        }
        minimum_approvals = 1
        # - trivy.yaml（リポジトリ直下）は Trivy が自動読込する設定ファイルで、ignorefile / ignore-policy により
        #   抑制先を差し替えられるため対象に含める。レビュー時はこの 2 項目が対象外のファイルを指していないかを確認する
        # - **/.semgrepignore は Semgrepignore v2（Semgrep 1.117 以降のデフォルト）でサブディレクトリの
        #   .semgrepignore も有効になるため対象に含める
        # - zizmor の設定はワークフロー側（.github/actions/zizmor の --config / --no-config）で .github/zizmor.yml に固定しているため、
        #   自動探索され得る他パス（リポジトリ直下の zizmor.yml 等）の列挙は不要
        file_patterns = [
          ".gitleaksignore",
          ".gitleaks.toml",
          ".trivyignore",
          ".trivyignore.yaml",
          "trivy.yaml",
          ".github/trivy-image.yml",
          ".github/trivy-image.yaml",
          ".github/zizmor.yml",
          ".semgrepignore",
          "**/.semgrepignore",
          "ghalint.yml",
          "ghalint.yaml",
          ".ghalint.yml",
          ".ghalint.yaml",
          ".github/ghalint.yml",
          ".github/ghalint.yaml",
        ]
      }
    }
  }
}

# 必須ワークフローの実体（この repo の .github/workflows/）を変更する PR に、security チームの承認を必須にする。
# 必須ワークフローはこの repo の main 上の定義を参照しているため、検知を弱める変更（severity の引き下げ・exit-code: 0 化など）が
# 通常の承認（pull_request_approval）だけで通ると、org 全体の検知が無効化されてしまう。
# Claude ワークフロー（.github/workflows/claude*.yml）も呼び出し側の全リポジトリで write 権限付きのプロンプトとして動くため、対象に含まれる。
# 必須ワークフローは、検知の処理（ツールのオプション・インライン ignore の禁止など）を composite action（.github/actions/）に置き、
# SHA で参照している。参照する SHA を上げる PR だけでは処理の差分が見えないため、action の変更も対象にする。
# レビューでは、参照する SHA が main に含まれるコミットであることも確認する。
# このルールセット自体の定義（terraform/github/）も、検知を弱められるため対象に含める
resource "github_organization_ruleset" "workflow_change_review" {
  name        = "🛠️ 検知ワークフロー変更の承認必須化"
  target      = "branch"
  enforcement = "active"

  bypass_actors {
    actor_type  = "Integration"
    actor_id    = local.renovate_app_id
    bypass_mode = "pull_request"
  }

  dynamic "bypass_actors" {
    for_each = local.single_approver ? [true] : []
    content {
      actor_type  = "OrganizationAdmin"
      bypass_mode = "always"
    }
  }

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
    repository_id = [local.required_workflow_repository_id]
  }

  rules {
    pull_request {
      # 承認の必須化は required_reviewers で行う
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = true
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = false
      allowed_merge_methods             = local.all_merge_methods

      required_reviewers {
        reviewer {
          id   = tonumber(github_team.security.id)
          type = "Team"
        }
        minimum_approvals = 1
        file_patterns     = [".github/workflows/**", ".github/actions/**", "terraform/github/**"]
      }
    }
  }
}

# ワークフロー定義・シェルスクリプト・Terraform・Python・TypeScript の検査と、バンドルサイズの増減のコメント（style.yml）。
# ランナーで依存を導入できない repo は、bypass ではなく conditions で対象から外す（docs/SETUP.md の「例外運用」）
resource "github_organization_ruleset" "style_check" {
  name        = "✏️ スタイルチェック"
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    required_workflows {
      do_not_enforce_on_create = true

      required_workflow {
        repository_id = local.required_workflow_repository_id
        path          = ".github/workflows/style.yml"
        ref           = "refs/heads/main"
      }
    }
  }
}

# 秘密鍵や .env などの機密ファイルを、履歴に入る前にサーバー側で拒否する
# （Gitleaks は PR 時の検知のため、検知された時点で秘密情報はリモートの履歴に残っている）。
# ファイル内容に対するコミット前のローカル検知は、各リポジトリの git hook（任意運用）が担う
resource "github_organization_ruleset" "sensitive_files" {
  name        = "🚫 機密ファイルの push 禁止"
  target      = "push"
  enforcement = "active"

  conditions {
    repository_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    # .env.example 等のテンプレートを誤ブロックしないよう .env.* は対象にしない（実値が入った .env.* は Gitleaks が検知する）
    file_path_restriction {
      restricted_file_paths = [
        ".env",
        "**/.env",
        "id_rsa",
        "**/id_rsa",
        "id_ed25519",
        "**/id_ed25519",
      ]
    }

    # tfplan（terraform plan -out の出力）は、sensitive な値も含めて平文で入る
    file_extension_restriction {
      restricted_file_extensions = [
        "*.pem",
        "*.key",
        "*.p12",
        "*.pfx",
        "*.jks",
        "*.keystore",
        "*.tfstate",
        "*.tfplan",
      ]
    }

    max_file_size {
      max_file_size = 5
    }
  }
}

# 付けたタグが別のコミットに付け替えられると、呼び出し側の `@<SHA>  # vX.Y.Z` のコメントと実際の SHA がずれ、
# Renovate の更新も壊れるため、リリースタグの更新・削除を禁止する。誤ったタグを付けた場合も付け替えず、修正を入れた次のバージョンを出す
resource "github_organization_ruleset" "release_tags" {
  name        = "🔒 リリースタグの変更禁止"
  target      = "tag"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["refs/tags/v*"]
      exclude = []
    }
    repository_id = [local.required_workflow_repository_id]
  }

  rules {
    update           = true
    deletion         = true
    non_fast_forward = true
  }
}
