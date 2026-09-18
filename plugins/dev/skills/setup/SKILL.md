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
`https://github.com/{組織アカウント}/github-workflows` (実際は、具体的な組織アカウント名を指定) を参照して、対象リポジトリに導入できる caller の github workflows を実装してください。
