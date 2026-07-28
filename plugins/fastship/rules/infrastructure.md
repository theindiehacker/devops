---
description: Terraform やインフラ関連の変更時に適用
summary: Terraform はローカル実行せず PR 経由で CI から適用する。シークレットは Secret Manager 管理で .env はコミットしない
paths:
  - "infrastructure/**/*.tf"
  - "infrastructure/**/*.hcl"
---

# インフラルール

## Terraform

- Terraform コマンドはローカルで実行しない（GitHub Actions から実行）
- `terraform plan` の確認は CI の出力を参照する
- 変更は必ず PR を経由し、レビューを受けること

## 環境変数・シークレット

- `.env` ファイルはコミットしない
- ローカル環境では `.env.local` を使用
- シークレットは GCP Secret Manager で管理
- ただし **Terraform がリソース作成時に入力として必要とする CI 専用シークレット**（例: 通知チャンネル作成用の Slack auth token）は、GitHub Environment secret → `TF_VAR_*` で供給する。線引きは「アプリのランタイムが読むシークレット = Secret Manager / Terraform の plan・apply の入力になるクレデンシャル = GitHub Environment secret」。前者は Terraform 管理下の Secret Manager に格納し、後者は tfstate に平文で載らないよう `sensitive = true` の変数で受ける
- シークレット混入は gitleaks で機械的にブロックする（pre-commit / CI で差分検査、`.gitleaks.toml` で誤検知を管理）。誤検知の除外は `.gitleaks.toml` の許可リストに限定し、実シークレットを許可リストで握り潰さない