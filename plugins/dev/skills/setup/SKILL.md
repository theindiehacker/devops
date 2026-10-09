---
name: setup
description: 対象リポジトリに組織推奨の開発スタックを導入し、コミット・PR 作成まで行う。導入済みのリポジトリでは最新版に更新する。使い方 → /dev:setup [owner/repo]
argument-hint: "[owner/repo]"
---

# セットアップ手順
## 1. ボイラープレートの導入
Organization アカウントにあるテンプレートリポジトリを確認し、対象リポジトリに導入してください。

 - テンプレートリポジトリが複数ある場合は、ユーザーに確認・提案してください。
 - テンプレートリポジトリがない場合はスキップしてください。

## 2. GitHub Actions の実装
`https://github.com/{組織アカウント}/devops` (実際は、具体的な組織アカウント名を指定) を参照して、対象リポジトリに導入できる caller の github workflows を実装してください。

## 3. tflint 設定の導入
Terraform (`*.tf`) を含むリポジトリでは、`https://github.com/{組織アカウント}/devops` の `.github/workflows/tflint.yml` にある `TFLINT_HCL` と同じ内容で、リポジトリ直下に `.tflint.hcl` を作成してください (既にある場合は上書き)。

 - CI はこのファイルを読まず `tflint.yml` の設定で固定しているため、ローカル実行 (`tflint --recursive --config="$(pwd)/.tflint.hcl"`) を CI と揃えるためのものです。
 - サブディレクトリの `.tflint.hcl` は削除してください。
 - `tflint-ignore` コメントは CI で禁止されているため、削除して違反を修正してください。
