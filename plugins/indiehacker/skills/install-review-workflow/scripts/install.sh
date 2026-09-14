#!/usr/bin/env bash
# caller ワークフロー (.github/workflows/claude-review.yml) を生成・更新する。
#
# 使い方:
#   install.sh <40桁の commit SHA> [リポジトリルート]
#
# 標準出力に結果を 1 行だけ出す。SKILL.md 側はこれで分岐する:
#   created            … 新規作成した
#   unchanged          … 既存が生成物と完全一致。何も書いていない
#   updated <旧SHA>    … 本スクリプトの生成物で SHA だけ違ったので更新した
#   conflict           … 手編集または別物。**何も書いていない**（呼び出し側で要確認）
#
# YAML は quoted heredoc で持つ。${{ }} をシェルに展開させないため、クォートを外さないこと。
set -euo pipefail

REF="${1:-}"
ROOT="${2:-.}"

if ! printf '%s' "$REF" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "install.sh: 第 1 引数は 40 桁の commit SHA である必要があります: '${REF}'" >&2
  exit 2
fi

TARGET="${ROOT}/.github/workflows/claude-review.yml"

render() {
  # $1 = 埋め込む SHA
  sed "s/__REF__/$1/g" <<'YAML'
name: "🧠 [Claude] Review"

# theindiehacker/github-workflows の reusable workflow を呼ぶだけの薄い caller。
# /indiehacker:install-review-workflow が生成・更新する。手で編集すると再実行時に確認が入る。
#
# 実行条件 (PR が open・コメント完全一致・Bot 除外・author_association) は呼び出し先の job `if` が
# 単一情報源として持つ (pwn request 対策)。ここに条件を複製しないこと。
#
# ⚠️ issue_comment は常にデフォルトブランチ版の定義で実行されるため、main にマージするまで起動しない。

on:
  # 呼び出し先の job `if` が github.event.issue / github.event.comment を読むため issue_comment 固定
  issue_comment:
    types: [created]

# write は job 側でのみ与える
permissions: {}

# concurrency をここに置かないこと。無関係なコメントで実行中のレビューが巻き添えキャンセルされる
# (PR 単位の束ねは呼び出し先 job の concurrency が行う)

jobs:
  # PR に `/code-review` (または `/code-review fable`) とコメントすると起動する
  code-review:
    # ref は full length commit SHA で固定する (ghalint 008 / zizmor unpinned-uses)。
    # 更新は /indiehacker:install-review-workflow の再実行で行う
    uses: theindiehacker/github-workflows/.github/workflows/claude-code-review.yml@__REF__  # main
    # 呼び出し先 job の permissions は caller job の permissions を超えられないため、同じ集合を与える
    permissions:
      contents: read
      pull-requests: write
      issues: write       # 進捗コメントの更新は issue comments API 経由
      id-token: write
    # `secrets: inherit` は使わないこと (ghalint deny_inherit_secrets)。
    # 組織シークレットはどちらか一方のみ登録されている前提で、未登録側は空文字として渡る
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}

  # PR に `/security-review` とコメントすると起動する
  security-review:
    uses: theindiehacker/github-workflows/.github/workflows/claude-security-review.yml@__REF__  # main
    permissions:
      contents: read
      pull-requests: write
      issues: write
      id-token: write
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
YAML
}

write() {
  mkdir -p "$(dirname "$TARGET")"
  render "$REF" > "$TARGET"
}

if [ ! -f "$TARGET" ]; then
  write
  echo "created"
  exit 0
fi

if render "$REF" | cmp -s - "$TARGET"; then
  echo "unchanged"
  exit 0
fi

# 既存が「本スクリプトの生成物で SHA だけ違う」かを判定する。
# 判定できない (手編集・旧世代) 場合は書かずに conflict を返す。
OLD_REF=$(grep -oE 'claude-code-review\.yml@[0-9a-f]{40}' "$TARGET" | head -1 | cut -d@ -f2 || true)
if [ -n "$OLD_REF" ] && render "$OLD_REF" | cmp -s - "$TARGET"; then
  write
  echo "updated ${OLD_REF}"
  exit 0
fi

echo "conflict"
exit 0
