# indiehacker

theindiehacker 全社共通の開発ワークフロープラグイン。既存プロダクトの `.claude/` で運用してきた DDD ワークフローを、どのリポジトリでも使えるように移植したもの。

## 提供するもの

### スキル

| スキル | 役割 |
|---|---|
| `/indiehacker:issue {内容}` | 非エンジニア向け。要望をヒアリングして GitHub Issues に Backlog を起票する |
| `/indiehacker:refine {Issue番号}` | Backlog をリファインメント。`/indiehacker:design` → Plan エージェントで実装可能な Todo にする |
| `/indiehacker:design {Issue番号}` | DDD でドメインモデル設計書を作成 → Artifact でレビュー → 承認後に Issue 説明欄へ反映 |
| `/indiehacker:dev {Issue番号}` | 実装 → PR 作成 → 自動レビュー待機 → `[must]` 自己修復 → APPROVED まで自走 |
| `/indiehacker:push-pr` | PR テンプレートに従った PR 作成・更新・Draft 解除・Diff コメント・レビュー対応 |
| `/indiehacker:conform [--fix] [diff範囲]` | 変更 diff を規約に照らして違反を洗い出す (`--fix` で修正まで適用) |

### エージェント

| エージェント | 役割 |
|---|---|
| `indiehacker:tdd` | Todo Issue の達成基準から受入テストのスケルトンを生成する (TDD の起点) |
| `indiehacker:domain-model-reviewer` | 実装差分を DDD の観点で鑑定する PR 前ゲート (貧血ドメイン・集約境界越え Tx 等) |

### 規約 (rules/)

DDD 実装規約のハンドブック (集約・値オブジェクト・ドメインイベント・リポジトリ・アプリケーション層・テスト・マイグレーション・E2E・インフラ)。各ファイルの frontmatter `paths` が対象ファイルの glob を定義する。

Claude Code はプラグイン内の rules をネイティブに自動ロードしないため、配信は rules-guard フックが担う (下記)。**プロジェクト側の `.claude/rules/` に同じ相対パスのファイルを置くと、そちらが優先される** (リポジトリ固有の上書き)。

### フック

| フック | イベント | 役割 |
|---|---|---|
| `rules-guard.py` | PreToolUse (Read\|Edit\|Write) | 対象ファイルにマッチする規約の要点 (summary) をセッション初回のみ注入する。プラグイン同梱 rules + プロジェクト `.claude/rules/` の両方を突合する |
| `pre-bash.sh` | PreToolUse (Bash) | `--no-verify` と、ローカルでの `terraform apply / destroy` をブロックする |
| `post-write-style.sh` | PostToolUse (Edit\|Write) | Taskfile に `style:fix` / `style:check` が定義されているリポジトリでのみ自動整形・静的検査を実行する (無ければ何もしない) |

## 前提

- `gh` CLI (認証済み) — issue / design / dev / push-pr スキルが使用
- `jq` — pre-bash フックが使用。**無いとフックが Bash をブロックする** (検査できない状態で素通しさせないため)
- `python3` (3.9 以上) — rules-guard フックと conform スキルが使用
- 依存プラグイン: `security-guidance@claude-plugins-official` — `plugin.json` の `dependencies` で宣言しているため、indiehacker を有効にすると自動で有効になる (公式マーケットプレイスは Claude Code に既定で登録済み)
- 任意: `feature-dev@claude-plugins-official` — `/indiehacker:dev` の実装ステップで使う。未インストールなら Claude が直接実装するので必須ではない
- Issue / PR テンプレートは org 共通リポジトリ [theindiehacker/.github](https://github.com/theindiehacker/.github) を正本とする。`/indiehacker:issue` は `.github/ISSUE_TEMPLATE/backlog.md`、`/indiehacker:push-pr` は `.github/PULL_REQUEST_TEMPLATE.md` を `gh api` で取得して使う。各リポジトリに同名のテンプレートがあればそちらが優先される (GitHub の default community health files の仕様どおり)
- 一部スキルはリポジトリ側の資産を前提とする (無い場合は該当ステップをスキップして動く):
  - `.github/workflows/claude-code-review.yml` / `claude-fix-on-fail.yml` / `claude.yml` (`/indiehacker:dev` の自動レビューループ)
  - `Taskfile.yml` の `style:fix` / `style:check` / `dev:test` タスク

## 移植しなかったもの

- `hooks/session-start.sh` — Claude Code Web のコンテナセットアップ (uv / bun / Docker) がプロジェクト固有
- `hooks/pre-write.sh` — OpenAPI 自動生成ファイルの編集禁止パスがプロジェクト固有
- プロダクト固有のローカル起動・スモークテストスキル — 対象プロダクトの起動手順に密結合
- `settings.json` の permissions / PostToolUse 直書き — permissions はプラグインで配布できないため各リポジトリの `.claude/settings.json` に残す (PostToolUse の `task style:*` は `post-write-style.sh` として移植済み)

これらは引き続き各リポジトリの `.claude/` に置く。
