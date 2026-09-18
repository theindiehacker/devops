---
name: setup-github-workflows
description: 対象リポジトリに組織推奨の github actions の caller ワークフローを作成し、コミット・PR 作成まで行う。導入済みのリポジトリでは固定している commit SHA を最新に更新する。使い方 → /dev:setup-github-workflows [owner/repo]
argument-hint: "[owner/repo]"
model: sonnet
---

https://github.com/{組織アカウント}/github-workflows (実際は、具体的な組織アカウント名を指定) を参照して、対象リポジトリに導入できる caller の github workflows を実装してください。