---
name: install-review-workflow
description: 対象リポジトリに Claude レビュー reusable workflow (github-workflows) を呼ぶ caller ワークフロー (.github/workflows/claude-review.yml) を作成し、コミット・PR 作成まで行う。PR に /code-review・/security-review とコメントするとレビューが走る状態にするための初期セットアップ。導入済みのリポジトリでは固定している commit SHA を最新に更新する。使い方 → /indiehacker:install-review-workflow [owner/repo]
argument-hint: "[owner/repo]"
model: sonnet
---

# レビューワークフローの導入 (install-review-workflow)

対象リポジトリに `.github/workflows/claude-review.yml` を置き、**PR に `/code-review` / `/security-review`
とコメントすると Claude のレビューが走る**状態にする。中身は `github-workflows` リポジトリの reusable workflow
(`claude-code-review.yml` / `claude-security-review.yml`) を呼ぶだけの薄い caller。

すでに導入済みのリポジトリで再実行すると、固定している commit SHA を `main` の最新に更新する。

> **org 名をハードコードしないこと。** このプラグインと `github-workflows` は複数の組織へ複製される前提で、
> 参照先は**導入先リポジトリの owner から実行時に導出**する。特定の org 名を SKILL.md・スクリプト・
> 生成物のいずれにも書き込まない。

## 手順

### 1. 対象リポジトリ・参照先・SHA の確定

**必ず 1 回の `Bash` 呼び出しで実行する。** Bash ツールはシェル変数を呼び出し間で保持しないため、
分割すると `OWNER` / `WORKFLOWS_REPO` / `REF` が失われる。

参照先 (`WORKFLOWS_REPO`) は次の順で決める:

1. **引数 `$ARGUMENTS` に `owner/repo` が渡されていればそれを使う**（別 org の共通リポジトリを参照する場合）
2. 無ければ **`${OWNER}/github-workflows`**（導入先と同じ org に置く既定の運用）

ref はブランチ名ではなく **40 桁の commit SHA** で固定する。必須チェックの ghalint
(`action_ref_should_be_full_length_commit_sha`) と zizmor (`unpinned-uses`) が、`uses:` が job 単位でも
SHA 固定を要求するため、`@main` では **PR がマージできない**（実測確認済み）。

```bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel) || { echo "NOT_A_GIT_REPO"; exit 0; }
OWNER=$(gh repo view --json owner -q .owner.login)
REPO_VIS=$(gh repo view --json visibility -q .visibility)

# 引数優先。無ければ導入先と同じ org の github-workflows を既定にする（org 名はハードコードしない）
ARG=$(printf '%s' "$ARGUMENTS" | tr -d '[:space:]')
WORKFLOWS_REPO="${ARG:-${OWNER}/github-workflows}"

# 参照先が読めるか確認する。読めない = 存在しないか権限不足
if ! WF=$(gh repo view "$WORKFLOWS_REPO" --json visibility,defaultBranchRef 2>/dev/null); then
  echo "WORKFLOWS_REPO_UNREACHABLE $WORKFLOWS_REPO"
  exit 0
fi
WF_VIS=$(echo "$WF" | jq -r .visibility)
DEFAULT_BRANCH=$(echo "$WF" | jq -r .defaultBranchRef.name)

# private の reusable workflow は「同じ org の private リポジトリ」からしか呼べない
if [ "$WF_VIS" = "PRIVATE" ]; then
  if [ "${WORKFLOWS_REPO%%/*}" != "$OWNER" ]; then
    echo "INCOMPATIBLE cross-org: 参照先が private のため別 org からは呼べない"; exit 0
  fi
  if [ "$REPO_VIS" = "PUBLIC" ]; then
    echo "INCOMPATIBLE public-caller: 参照先が private のため public リポジトリからは呼べない"; exit 0
  fi
fi

REF=$(gh api "repos/${WORKFLOWS_REPO}/commits/${DEFAULT_BRANCH}" --jq .sha 2>/dev/null || true)
if ! printf '%s' "$REF" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "REF_UNRESOLVED"; exit 0
fi

echo "OK ROOT=$ROOT WORKFLOWS_REPO=$WORKFLOWS_REPO REF=$REF WF_VIS=$WF_VIS"
```

出力の見方（`OK` 以外はすべて中断し、理由を説明する）:

| 出力 | 対応 |
|---|---|
| `NOT_A_GIT_REPO` | git リポジトリ内で実行するよう案内する |
| `WORKFLOWS_REPO_UNREACHABLE <slug>` | リポジトリ名が既定 (`github-workflows`) と違うなら `/indiehacker:install-review-workflow owner/repo` で明示するよう案内。private なら `gh auth status` で権限を確認するよう案内 |
| `INCOMPATIBLE cross-org` | 参照先が private のため別 org からは呼べない。参照先を public にするか、同じ org に複製する必要がある |
| `INCOMPATIBLE public-caller` | 参照先が private のため public リポジトリからは呼べない |
| `REF_UNRESOLVED` | デフォルトブランチの SHA を解決できなかった。権限とリポジトリ名を確認する |
| `OK ...` | 続く値をステップ 2 で使う |

### 2. ファイルを生成

生成は同梱スクリプトに委ねる（YAML をバイト単位で一定に保ち、再実行時の差分判定を成立させるため）。

**ステップ 1 の変数は引き継がれない**（Bash ツールは呼び出し間でシェル変数を保持しない）。
`WORKFLOWS_REPO` / `REF` / `ROOT` は、ステップ 1 が `OK` 行で出力した値を**リテラルで埋めて**実行する。
`${CLAUDE_PLUGIN_ROOT}` は hooks.json 専用で Bash ツールでは展開されないため、導入先を実際に探す:

```bash
# ステップ 1 の OK 行の値をそのまま埋める
WORKFLOWS_REPO="{ステップ1のWORKFLOWS_REPO}"
REF="{ステップ1のREF}"
ROOT="{ステップ1のROOT}"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ ! -d "${PLUGIN_ROOT:-/nonexistent}/rules" ]; then
  PLUGIN_ROOT=$(find "$HOME/.claude/plugins" "${CLAUDE_PROJECT_DIR:-.}/.claude/plugins" \
    -maxdepth 6 -type d -path '*/indiehacker/*' -name rules 2>/dev/null | head -1)
  PLUGIN_ROOT="${PLUGIN_ROOT%/rules}"
fi
if [ ! -d "${PLUGIN_ROOT:-/nonexistent}/rules" ]; then
  echo "PLUGIN_ROOT_NOT_FOUND"
else
  bash "$PLUGIN_ROOT/skills/install-review-workflow/scripts/install.sh" \
    "$WORKFLOWS_REPO" "$REF" "$ROOT"
fi
```

`PLUGIN_ROOT_NOT_FOUND` なら、**導入を実行できなかった**旨を報告して停止する（黙って進まない）。

スクリプトは結果を 1 行だけ返すので、それで分岐する:

| 出力 | 意味 | 対応 |
|---|---|---|
| `created` | 新規作成した | ステップ 3 へ |
| `unchanged` | 既存が生成物と完全一致 | 「すでに最新で変更なし」と報告して終了（コミットしない） |
| `updated <旧slug> <旧SHA>` | 参照先を更新した | 旧→新を報告してステップ 3 へ。slug が同じなら `https://github.com/<slug>/compare/<旧SHA>...<新SHA>` も添える |
| `conflict` | 手編集または別物。**書いていない** | ステップ 2-a へ |

#### 2-a. `conflict` の場合

既存ファイルと生成内容の差分を提示し、`AskUserQuestion` で
**「生成物で置き換える / 中断する / 既存を退避して置き換える」** を確認する。
**回答を得るまで書き込まない**。置き換える場合のみ、既存を削除してから再度スクリプトを実行する。

### 3. コミットと PR 作成

`Skill` ツールから `/indiehacker:push-pr` を呼び出す。PR 本文には以下を必ず含める:

- 何を入れたか（caller ワークフロー 1 ファイル）と、参照先 slug・固定した SHA
- **`.github/workflows/**` の変更は org ルールセットによりセキュリティチームの承認が必須になっている場合がある**
  （`github-workflows` の `docs/SETUP.md`「検知ワークフロー変更の承認必須化」）
- 下記「既知の問題」

### 4. 最後に必ず伝えること

- ⚠️ **既知の問題**: 参照先が **private の場合**、この PR は必須チェック **zizmor が fatal エラーで落ちる**。
  caller の `${{ github.token }}` では参照先を読めず、`impostor-commit` 監査が例外終了するため。
  **findings ではないので `.github/zizmor.yml` の `ignore:` では抑制できない**。
  `github-workflows` 側で zizmor に参照先を読めるトークンを渡す対応が必要（別 Issue）。
- **デフォルトブランチにマージするまで起動しない**。`issue_comment` は常にデフォルトブランチ版の定義で実行されるため。
- コメントは**完全一致**。`/code-review`・`/code-review fable`（Fable 5.1 でレビュー）・`/security-review` の 3 つだけで、
  前後に文字を足すと起動しない（`/code-review お願いします` は動かない）。
- 起動できるのは PR が **open** で、コメント投稿者が **OWNER / MEMBER / COLLABORATOR** かつ Bot でない場合のみ。
- 前提設定（未設定ならレビューは失敗する）は参照先リポジトリの `docs/SETUP.md` を参照:

| 前提 | SETUP.md の節 |
|---|---|
| 参照先 → Settings → Actions → General → Access = org 内から参照可（参照先が private の場合に必須） | 「本リポジトリの Access」 |
| 組織シークレット `CLAUDE_CODE_OAUTH_TOKEN` **または** `ANTHROPIC_API_KEY` をどちらか一方だけ登録 | 「組織シークレットを登録する」 |
| Claude GitHub App を org に install | 「Claude GitHub App をインストールする」 |
| Actions permissions が `anthropics/claude-code-action@*` / `oven-sh/setup-bun@*` を許可 | 「Actions permissions」 |

## 注意事項

- **org 名をハードコードしない**。参照先は導入先リポジトリの owner から導出するか、引数で受け取る。
  このプラグインは複数の組織へ複製されるため、特定の org を前提にした記述を増やさないこと。
- **実行条件を caller に複製しない**。PR が open か・コメント完全一致・Bot 除外・author_association の判定は
  呼び出し先の job `if` が単一情報源として持つ（pwn request 対策）。caller 側に `if` を足すと二重管理になる。
- **`secrets: inherit` を使わない**。ghalint `deny_inherit_secrets` で落ちるため、明示的に列挙する。
- **`timeout-minutes` を caller job に書かない**。`uses:` job には指定できない。
- **`permissions` を caller job から削らない**。呼び出し先 job の permissions は caller を超えられないため、
  削ると呼び出し先が write を得られずレビューを投稿できない。
- 参照先にタグが無い場合、Renovate は SHA に追随できない。更新は本スキルの再実行で行う。
