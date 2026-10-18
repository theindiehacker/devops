---
name: setup
description: 対象リポジトリに組織推奨の開発スタックを導入し、コミット・PR 作成まで行う。Issue のラベルで Claude Code on the web が実装を始めるラベル駆動開発 (ラベルとルーティン) も用意する。導入済みのリポジトリでは最新版に更新する。使い方 → /dev:setup [owner/repo]
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

## 4. Taskfile / lefthook / mise の導入
`https://github.com/{組織アカウント}/devops` の README「📦 共通設定の配布」に従って、次のファイルを置いてください (既にある場合は最新版に更新)。参照するタグは devops の最新のリリースタグにしてください。

 - `Taskfile.yml` / `lefthook.yml`: devops をタグで参照する
 - `mise.toml` / `mise.lock`: devops の同じタグからコピーする
 - `.gitignore`: `.task/` を追加する

## 5. Claude Code on the web のセットアップ
devops の `docs/CLAUDE-WEB-SETUP.md` に従って、`.claude/settings.json` の `hooks.SessionStart` に、devops の `scripts/claude-web-setup.sh` を 4 と同じタグで取得・実行する hook を追加してください (既存の設定は残す)。

## 6. ラベル駆動開発のセットアップ
Issue に `claude:implement` ラベルを付けると Claude Code on the web が実装を始めるように、ラベルとルーティンを用意してください。リポジトリへのコミットは伴いません。

### 6.1 ラベル
次のコマンドでラベルを作成してください (既にある場合は上書き)。

```bash
gh label create claude:implement --color d97757 --description "🧠 Claude Code on Web で開発を開始する" --force -R {owner/repo}
```

### 6.2 ルーティン
RemoteTrigger ツールで、実行者の claude.ai アカウントに次のルーティンを用意してください。

| 項目 | 値 |
|:--|:--|
| 名前 | `{リポジトリ名} / 実装` |
| リポジトリ | 対象リポジトリのみ |
| 環境 | 既存の ` / 実装` ルーティンと同じ環境 (無ければユーザーに確認) |
| モデル | `claude-opus-5-5` |
| コネクタ | なし |
| 通知 | プッシュ通知のみ |
| トリガー | 対象リポジトリの Issue にラベルが付いたとき (`issues.labeled`)。Issue のラベルに `claude:implement` を含む場合だけ |
| プロンプト | 下記 |

```text
Issue の内容を確認し、着手してください。

 - 不明点や質問がある場合は着手する前にチャットで質問してください
 - PR を作成/更新したら、`/code-review`, `/security-review` コメントを投稿し、Claude によるレビューを実施してください
 - Claude からレビューが投稿されたら、コメントを確認し、採否の判断・対応・返信まで行ってください
```

1. `list` で既存のルーティンを探してください。名前が ` / 実装` で終わり、`job_config.ccr.session_context.sources` の先頭が対象リポジトリのものを既存とみなします (名前がリポジトリ名と違うものもあるため)。
2. 既存のルーティンがある場合は、`get` で取得した `job_config` のプロンプト (`ccr.events[0].data.message.content`) とモデル (`ccr.session_context.model`) だけを差し替えて `update` してください。`job_config` は一部だけ送らず、追加のリポジトリなど他の値も取得したまま送ってください。名前・コネクタ・トリガーは変えないでください。
3. 既存のルーティンがない場合は、次の順に作成してください。
   1. `create`: body の書き方は `/schedule` スキルに従う。ただし `cron_expression` / `run_once_at` は付けず、`session_context` に `"autofix_on_pr_create": true` を付ける (UI で作ったときの既定値)
   2. `update`: `{"clear_mcp_connections": true, "notifications": {"channel": {"email": false, "push": true, "slack": false}}}` を送る (`create` でコネクタを省くと、claude.ai に接続済みのコネクタがすべて付くため)
   3. `create_webhook_trigger`: 次の body で GitHub トリガーを追加する

```json
{
  "routine_trigger_id": "{作成したルーティンの ID}",
  "source": "github",
  "hook_type": "app",
  "scope_id": "{owner/repo}",
  "events": ["issues.labeled"],
  "filter": {"clauses": [{"field": "issue.labels", "op": "FILTER_OP_IN", "values": ["claude:implement"]}]}
}
```

 - 追加済みのトリガーは API から確認できず重複に気づけないため、既存のルーティンにはトリガーを追加しないでください。
 - RemoteTrigger が使えない場合 (claude.ai 以外でログインしているなど) や、Claude GitHub App が未インストールでトリガーを追加できない場合は、6.2 をスキップし、devops の README「🤖 Claude Code on Web」の手動手順をユーザーに案内してください。
 - 作成・更新したルーティンの URL (`https://claude.ai/code/routines/{ID}`) をユーザーに伝えてください。
