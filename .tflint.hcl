# 全リポジトリ共通の tflint の設定（Taskfile.yml の style:check:tflint が TFLINT_CONFIG_FILE で渡す）。
# 対象 repo の .tflint.hcl は読まず、インラインの tflint-ignore コメントも禁止している。
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "all"
}

plugin "google" {
  enabled = true
  version = "0.40.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
