---
name: terraform
description: Terraform やインフラ関連の変更時に適用
paths:
  - "**/*.tf"
  - "**/*.hcl"
user-invocable: false
---
# 実装ルール
## 目的

**人間**が最短時間でコードを理解できるようにする

## 実装ルール

 - [一般的なスタイルと構造に関するベストプラクティス](https://docs.cloud.google.com/docs/terraform/best-practices/general-style-structure.md.txt?hl=ja) に沿って実装されていること
 - 活用できる公式のモジュールがあれば、積極的に活用すること
   - Google Cloud: [Terraform ブループリントとモジュール](https://docs.cloud.google.com/docs/terraform/blueprints/terraform-blueprints.md.txt?hl=ja)
 - 公式推奨・業界標準・ベストプラクティスにすること
 - `main.tf` が大きくなったら機能単位で分割
   - 例: network.tf / compute.tf / storage.tf / iam.tf
   - 基準は「一緒に読む・一緒に変更するもの」を同じファイルに置く(=凝集度が高い)
   - リソース1個 = 1ファイルは細かすぎて非推奨
