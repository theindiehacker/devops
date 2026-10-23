# 実際の Organization には接続せず、mock_provider で plan だけを行う（CI に認証情報は渡さない）
mock_provider "github" {
  mock_data "github_rest_api" {
    defaults = {
      body = "{\"billing_email\":\"billing@example.com\",\"name\":\"example\",\"description\":null,\"company\":null,\"blog\":\"\",\"email\":null,\"location\":null,\"twitter_username\":null,\"two_factor_requirement_enabled\":true,\"has_organization_projects\":true,\"has_repository_projects\":true}"
    }
  }

  mock_data "github_organization_roles" {
    defaults = {
      roles = [
        { role_id = 8132, name = "all_repo_read", base_role = "read", description = "", permissions = [], source = "Predefined" },
        { role_id = 8134, name = "all_repo_write", base_role = "write", description = "", permissions = [], source = "Predefined" },
        { role_id = 138, name = "security_manager", base_role = "read", description = "", permissions = [], source = "Predefined" },
      ]
    }
  }

  mock_data "github_repository" {
    defaults = {
      repo_id = 100
    }
  }

  mock_data "github_app" {
    defaults = {
      id = "200"
    }
  }
}

run "必須ワークフローは_github_workflows_の_main_を参照する" {
  command = plan

  assert {
    condition     = [for w in github_organization_ruleset.security_scan.rules[0].required_workflows[0].required_workflow : w.path] == [".github/workflows/security.yml"]
    error_message = "🛡️ 脆弱性・IaC 設定ミス検知 は security.yml だけを必須にする"
  }

  assert {
    condition     = [for w in github_organization_ruleset.style_check.rules[0].required_workflows[0].required_workflow : w.path] == [".github/workflows/style.yml"]
    error_message = "✏️ スタイルチェック は style.yml だけを必須にする"
  }

  assert {
    condition = alltrue([
      for w in concat(
        tolist(github_organization_ruleset.security_scan.rules[0].required_workflows[0].required_workflow),
        tolist(github_organization_ruleset.style_check.rules[0].required_workflows[0].required_workflow),
      ) : w.repository_id == 100 && w.ref == "refs/heads/main"
    ])
    error_message = "必須ワークフローは github-workflows の main を参照する"
  }
}

run "必須ワークフローのルールセットは_bypass_できない" {
  command = plan

  assert {
    condition     = length(github_organization_ruleset.security_scan.bypass_actors) == 0 && length(github_organization_ruleset.style_check.bypass_actors) == 0
    error_message = "bypass を入れると、失敗した検査を無視してマージできるようになる"
  }

  assert {
    condition     = length(github_organization_ruleset.sensitive_files.bypass_actors) == 0 && length(github_organization_ruleset.release_tags.bypass_actors) == 0
    error_message = "機密ファイルの push 禁止とリリースタグの変更禁止は bypass できない"
  }
}

run "Renovate_は_PR_のときだけ承認を_bypass_できる" {
  command = plan

  assert {
    condition = alltrue([
      for actor in concat(
        github_organization_ruleset.pull_request_approval.bypass_actors,
        github_organization_ruleset.workflow_change_review.bypass_actors,
      ) : actor.bypass_mode == "pull_request" if actor.actor_type == "Integration"
    ])
    error_message = "Renovate の bypass は PR のときだけにする"
  }
}

run "検知ワークフローとルールセットの定義の変更には_security_チームの承認が要る" {
  command = plan

  assert {
    condition = alltrue([
      for pattern in [".github/workflows/**", "terraform/github/**"] :
      contains(github_organization_ruleset.workflow_change_review.rules[0].pull_request[0].required_reviewers[0].file_patterns, pattern)
    ])
    error_message = "必須ワークフローの実体とルールセットの定義は、検知を弱められるため security チームの承認を必須にする"
  }
}

run "GITHUB_TOKEN_は_read_で_PR_を承認できない" {
  command = plan

  assert {
    condition     = github_actions_organization_workflow_permissions.this.default_workflow_permissions == "read"
    error_message = "GITHUB_TOKEN のデフォルト権限は read にする"
  }

  assert {
    condition     = github_actions_organization_workflow_permissions.this.can_approve_pull_request_reviews == false
    error_message = "GITHUB_TOKEN による自己承認で、承認を必須にするルールセットが迂回される"
  }
}

run "管理しない項目は今の値を渡す" {
  command = plan

  assert {
    condition     = github_organization_settings.this.billing_email == "billing@example.com"
    error_message = "billing_email は今の値をそのまま渡す"
  }

  assert {
    condition     = github_organization_settings.this.has_organization_projects == true
    error_message = "管理しない項目を既定値で上書きしない"
  }
}

run "二要素認証が必須でなければ警告する" {
  command = plan

  override_data {
    target = data.github_rest_api.organization
    values = {
      body = "{\"billing_email\":\"billing@example.com\",\"name\":\"example\",\"description\":null,\"company\":null,\"blog\":\"\",\"email\":null,\"location\":null,\"twitter_username\":null,\"two_factor_requirement_enabled\":false}"
    }
  }

  expect_failures = [check.two_factor_requirement]
}
