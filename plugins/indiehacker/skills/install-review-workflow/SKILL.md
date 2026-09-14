---
name: install-review-workflow
description: 対象リポジトリに theindiehacker/github-workflows の Claude レビュー reusable workflow を呼ぶ caller ワークフロー (.github/workflows/claude-review.yml) を作成し、コミット・PR 作成まで行う。PR に /code-review・/security-review とコメントするとレビューが走る状態にするための初期セットアップ。導入済みのリポジトリでは固定している commit SHA を最新に更新する。使い方 → /indiehacker:install-review-workflow
model: sonnet
---

# レビューワークフローの導入 (install-review-workflow)

対象リポジトリに `.github/workflows/claude-review.yml` を置き、**PR に `/code-review` / `/security-review`
とコメントすると Claude のレビューが走る**状態にする。中身は
[theindiehacker/github-workflows](https://github.com/theindiehacker/github-workflows) の reusable workflow
(`claude-code-review.yml` / `claude-security-review.yml`) を呼ぶだけの薄い caller。

すでに導入済みのリポジトリで再実行すると、固定している commit SHA を `main` の最新に更新する。

## 手順

### 1. 対象リポジトリの確認

```bash
ROOT=$(git rev-parse --show-toplevel)
gh repo view --json nameWithOwner,visibility,defaultBranchRef
```

以下は設定で解決できないので、該当したら**理由を説明して中断する**:

- git リポジトリでない
- owner が `theindiehacker` でない
- `visibility` が `PUBLIC` — `github-workflows` は private であり、private の reusable workflow は
  **同じ org の private リポジトリからしか呼べない**（`github-workflows/docs/SETUP.md` 3.「本リポジトリの Access」）

### 2. 固定する commit SHA を解決

ref はブランチ名ではなく **40 桁の commit SHA** で固定する。org の必須チェック ghalint
(`action_ref_should_be_full_length_commit_sha`) と zizmor (`unpinned-uses`) が、`uses:` が job 単位でも
SHA 固定を要求するため、`@main` では **PR がマージできない**（実測確認済み）。

```bash
REF=$(gh api repos/theindiehacker/github-workflows/commits/main --jq .sha)
printf '%s' "$REF" | grep -Eq '^[0-9a-f]{40}$' || echo "SHA を解決できませんでした"
```

解決できない場合は中断し、`gh auth status` で **theindiehacker org にアクセスできるアカウントか**確認するよう案内する
（`github-workflows` は private なので、読めない = 権限不足）。

### 3. ファイルを生成

生成は同梱スクリプトに委ねる（YAML をバイト単位で一定に保ち、再実行時の差分判定を成立させるため）。
`${CLAUDE_PLUGIN_ROOT}` は hooks.json 専用で Bash ツールでは展開されないため、導入先を実際に探す:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ ! -d "${PLUGIN_ROOT:-/nonexistent}/rules" ]; then
  PLUGIN_ROOT=$(find "$HOME/.claude/plugins" "${CLAUDE_PROJECT_DIR:-.}/.claude/plugins" \
    -maxdepth 6 -type d -path '*/indiehacker/*' -name rules 2>/dev/null | head -1)
  PLUGIN_ROOT="${PLUGIN_ROOT%/rules}"
fi
if [ ! -d "${PLUGIN_ROOT:-/nonexistent}/rules" ]; then
  echo "PLUGIN_ROOT_NOT_FOUND"
else
  bash "$PLUGIN_ROOT/skills/install-review-workflow/scripts/install.sh" "$REF" "$ROOT"
fi
```

`PLUGIN_ROOT_NOT_FOUND` なら、**導入を実行できなかった**旨を報告して停止する（黙って進まない）。

スクリプトは結果を 1 行だけ返すので、それで分岐する:

| 出力 | 意味 | 対応 |
|---|---|---|
| `created` | 新規作成した | ステップ 4 へ |
| `unchanged` | 既存が生成物と完全一致 | 「すでに最新で変更なし」と報告して終了（コミットしない） |
| `updated <旧SHA>` | SHA だけ更新した | 旧→新 SHA と `https://github.com/theindiehacker/github-workflows/compare/<旧>...<新>` を報告してステップ 4 へ |
| `conflict` | 手編集または別物。**書いていない** | ステップ 3-a へ |

#### 3-a. `conflict` の場合

既存ファイルと生成内容の差分を提示し、`AskUserQuestion` で
**「生成物で置き換える / 中断する / 既存を退避して置き換える」** を確認する。
**回答を得るまで書き込まない**。置き換える場合のみ、既存を削除してから再度スクリプトを実行する。

### 4. コミットと PR 作成

`Skill` ツールから `/indiehacker:push-pr` を呼び出す。PR 本文には以下を必ず含める:

- 何を入れたか（caller ワークフロー 1 ファイル）と、固定した SHA
- **`.github/workflows/**` の変更は org ルールセットによりセキュリティチームの承認が必須**
  （`github-workflows/docs/SETUP.md` 2.「🛠️ 検知ワークフロー変更の承認必須化」）
- 下記「既知の問題」

### 5. 最後に必ず伝えること

- ⚠️ **既知の問題**: 現状この PR は必須チェック **zizmor が fatal エラーで落ちる**。
  `github-workflows` が private で caller の `${{ github.token }}` では読めず、`impostor-commit` 監査が
  例外終了するため。**findings ではないので `.github/zizmor.yml` の `ignore:` では抑制できない**。
  `github-workflows` 側の対応が必要（別 Issue）。
- **main にマージするまで起動しない**。`issue_comment` は常にデフォルトブランチ版の定義で実行されるため。
- コメントは**完全一致**。`/code-review`・`/code-review fable`（Fable 5.1 でレビュー）・`/security-review` の 3 つだけで、
  前後に文字を足すと起動しない（`/code-review お願いします` は動かない）。
- 起動できるのは PR が **open** で、コメント投稿者が **OWNER / MEMBER / COLLABORATOR** かつ Bot でない場合のみ。
- 前提設定（未設定ならレビューは失敗する）は `github-workflows/docs/SETUP.md` を参照:

| 前提 | 参照 |
|---|---|
| `github-workflows` → Settings → Actions → General → Access = org 内から参照可 | SETUP.md 3.「本リポジトリの Access」 |
| 組織シークレット `CLAUDE_CODE_OAUTH_TOKEN` **または** `ANTHROPIC_API_KEY` をどちらか一方だけ登録 | SETUP.md 4.「組織シークレットを登録する」 |
| Claude GitHub App を org に install | SETUP.md 4.「Claude GitHub App をインストールする」 |
| Actions permissions が `anthropics/claude-code-action@*` / `oven-sh/setup-bun@*` を許可 | SETUP.md 3. Actions permissions |

## 注意事項

- **実行条件を caller に複製しない**。PR が open か・コメント完全一致・Bot 除外・author_association の判定は
  呼び出し先の job `if` が単一情報源として持つ（pwn request 対策）。caller 側に `if` を足すと二重管理になる。
- **`secrets: inherit` を使わない**。ghalint `deny_inherit_secrets` で落ちるため、明示的に列挙する。
- **`timeout-minutes` を caller job に書かない**。`uses:` job には指定できない。
- **`permissions` を caller job から削らない**。呼び出し先 job の permissions は caller を超えられないため、
  削ると呼び出し先が write を得られずレビューを投稿できない。
- タグが無いため Renovate は SHA に追随できない。更新は本スキルの再実行で行う。
