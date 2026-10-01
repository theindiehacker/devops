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

## ルール

 - 活用できる公式のモジュールがあれば、積極的に活用すること
   - [Google Cloud の Terraform ブループリントとモジュール](https://docs.cloud.google.com/docs/terraform/blueprints/terraform-blueprints.md.txt?hl=ja)
 - 公式推奨・業界標準・ベストプラクティスにすること

**Google Cloud**:

 - [一般的なスタイルと構造に関するベストプラクティス](https://docs.cloud.google.com/docs/terraform/best-practices/general-style-structure.md.txt?hl=ja)
