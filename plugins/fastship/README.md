# fastship

theindiehacker 全社共通の開発ワークフロープラグイン。fastship.jp の `.claude/` で運用してきた DDD ワークフローを、どのリポジトリでも使えるように移植したもの。

## 提供するもの

### スキル

| スキル | 役割 |
|---|---|
| `/fastship:issue {内容}` | 非エンジニア向け。要望をヒアリングして GitHub Issues に Backlog を起票する |
| `/fastship:refine {Issue番号}` | Backlog をリファインメント。`/fastship:design` → Plan エージェントで実装可能な Todo にする |
| `/fastship:design {Issue番号}` | DDD でドメインモデル設計書を作成 → Artifact でレビュー → 承認後に Issue 説明欄へ反映 |
| `/fastship:dev {Issue番号}` | 実装 → PR 作成 → 自動レビュー待機 → `[must]` 自己修復 → APPROVED まで自走 |
| `/fastship:push-pr` | PR テンプレートに従った PR 作成・更新・Draft 解除・Diff コメント・レビュー対応 |
| `/fastship:conform [--fix] [diff範囲]` | 変更 diff を規約に照らして違反を洗い出す (`--fix` で修正まで適用) |

### エージェント

| エージェント | 役割 |
|---|---|
| `fastship:tdd` | Todo Issue の達成基準から受入テストのスケルトンを生成する (TDD の起点) |
| `fastship:domain-model-reviewer` | 実装差分を DDD の観点で鑑定する PR 前ゲート (貧血ドメイン・集約境界越え Tx 等) |

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
- 任意: `feature-dev@claude-plugins-official` — `/fastship:dev` の実装ステップで使う。未インストールなら Claude が直接実装するので必須ではない
- 一部スキルはリポジトリ側の資産を前提とする (無い場合は該当ステップをスキップして動く):
  - `.github/workflows/claude-code-review.yml` / `claude-fix-on-fail.yml` / `claude.yml` (`/fastship:dev` の自動レビューループ)
  - `.github/PULL_REQUEST_TEMPLATE.md` / `.github/ISSUE_TEMPLATE/todo.md` (`/fastship:push-pr` / `/fastship:issue`)
  - `Taskfile.yml` の `style:fix` / `style:check` / `dev:test` タスク

## fastship.jp 由来で移植しなかったもの

- `hooks/session-start.sh` — Claude Code Web のコンテナセットアップ (uv / bun / Docker) がプロジェクト固有
- `hooks/pre-write.sh` — OpenAPI 自動生成ファイルの編集禁止パスがプロジェクト固有
- `skills/run-fastship-jp/` — fastship.jp のローカル起動・スモークテスト専用
- `settings.json` の permissions / PostToolUse 直書き — permissions はプラグインで配布できないため各リポジトリの `.claude/settings.json` に残す (PostToolUse の `task style:*` は `post-write-style.sh` として移植済み)

これらは引き続き各リポジトリの `.claude/` に置く。
