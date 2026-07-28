---
name: dev
description: GitHub Issue を引数に受け取り、実装 → PR 作成 → 自動レビュー待機 → CHANGES_REQUESTED の自己修復 → APPROVED まで一気通貫で進めるスキル。Claude Code Web (claude.ai/code) からスマホで起動して放置運用するためのもの。使い方 → /fastship:dev {GitHub Issue 番号}
---

# Issue 実装からマージ可能までの自走

claude.ai/code から `/fastship:dev {Issue 番号}` で起動し、実装 → `/fastship:push-pr` → 自動レビューを待機 → `[must]` を自己修復 → APPROVED まで持っていくためのスキル。スマホ運用を前提に、最後の Approve & Merge だけ人間に委ねる。

## 依存ワークフロー / 規約

このスキルは以下に依存している。挙動が変わった場合はここを更新する:

- `.github/workflows/claude-code-review.yml` — Ready for review の PR を自動レビュー。`[must]` 検出で PR を Draft に戻し、`<!-- claude-auto-fix:review-changes:{sha} -->` マーカー付きの `@claude` 自動修復依頼コメントを投稿する（PR あたり累計 3 回まで）
- `.github/workflows/claude-fix-on-fail.yml` — CI 失敗時に `<!-- claude-auto-fix:ci-fail:{sha} -->` マーカー付きの `@claude` 自動修復依頼コメントを投稿する（PR あたり累計 3 回まで）
- `.github/workflows/claude.yml` — `@claude` メンションでエージェントを起動するベースワークフロー。Bot 由来の `@claude` は `<!-- claude-auto-fix:` マーカー入りに限定
- このプラグインの push-pr スキル（`/fastship:push-pr`） — PR 作成・更新のセルフレビューと Ready 化までを担う
- プロジェクトの `CLAUDE.md` — 完了条件（テスト・Lint の通過、フックを `--no-verify` で迂回しない）とレビュー指摘プレフィックス規約（`[must]` / `[imo]` / `[nits]` / `[ask]`）

> `.github/workflows/claude-*.yml` はリポジトリ側の資産（会社テンプレートに同梱）。無いリポジトリでは自動レビュー待機（ステップ 5 以降)が成立しないため、その場合はステップ 4（PR 作成）までで完了として報告する。

## 手順

### 1. Issue の取得とスコープ確認

```bash
ISSUE_NUMBER={引数}
gh issue view "$ISSUE_NUMBER" --json title,body,labels
```

- ユーザーストーリー / 達成条件を読み、不明点があれば `AskUserQuestion` で確認する（claude.ai/code 経由なら通知が飛ぶ）
- `backlog` ラベルが付いている場合は **「先に `/fastship:refine` で Todo に分解した方がよくないか」を確認** する。Backlog をそのまま実装すると粒度が大きすぎることが多い

### 2. 作業ブランチを作成

```bash
git checkout main && git pull
git checkout -b "feature/issue-${ISSUE_NUMBER}"
```

ブランチが既に存在する場合は `feature/issue-${ISSUE_NUMBER}-2` など連番でフォールバックする。

### 3. 実装

`Skill` ツールから `/feature-dev` を呼び出して実装する。完了条件は CLAUDE.md に従う（`task style:check` / `task dev:test` の通過、フックを `--no-verify` で迂回しない 等）。

> `/feature-dev` は汎用プラグインで DDD 非対応。会社標準の規約（このプラグイン同梱の `rules/**`）とプロジェクトの `.claude/rules/**` は、このプラグインの rules-guard フック（PreToolUse: Read|Edit|Write）が対象パスに触れた初回に要点を注入するが、**実装対象パスにマッチするルールは書き始める前に全文を Read** する。実装をサブエージェント（`Agent` ツール）にファンアウトする場合は rules の自動ロードが保証されないため、該当ルールファイルのパスを prompt に明記して必ず Read させる。Issue 説明欄に `/fastship:design` のドメインモデル設計書（`<!-- domain-model-design -->` マーカー区間）があれば、その集約境界・不変条件・振る舞いに厳密に従う。

### 3.5. ドメインモデル鑑定ゲート（PR 前）

`backend/src/**/domain/**` または `**/application/**` に変更がある場合、PR を作る**前に** `Agent` ツールで `subagent_type: "fastship:domain-model-reviewer"` を呼び、DDD の意味論的スメル（貧血ドメイン・集約境界越え Tx・primitive obsession・ロジック漏れ・用語ドリフト）を鑑定する。Issue 番号を渡し、設計書と突き合わせさせる。

- `PASS`（`[must]` 無し）→ ステップ 4 へ。
- `CHANGES_REQUESTED`（`[must]` あり）→ **PR を作る前に自分で修正**する。集約メソッドへのロジック引き上げ・VO 化・イベント化など、鑑定士の直し方に従い、`task style:check` / `task dev:test` を通してから再度鑑定 → `PASS` になったらステップ 4 へ。
- 鑑定→修正→再鑑定は **最大 2 周** まで。2 周目でも同じ `[must]` が残る場合は設計自体に問題がある可能性が高いので、`AskUserQuestion` で「設計書に戻る（/fastship:design やり直し）/ 指摘を見送って PR を出す / 人間に引き継ぐ」を確認する（ステップ 8 と同型のエスカレーション）。
- ドメイン層に変更が無い純粋なインフラ/設定変更なら本ステップはスキップ可。

> 目的は「bot/人間レビューや自分の手戻りが起きる前に、DDD 崩れをローカルで潰す」こと。ここを通してから PR を出すことで、ステップ 5–7 のレビューループでの DDD 指摘を減らす。

### 4. PR 作成（Ready for review まで）

`Skill` ツールから `/fastship:push-pr` を呼び出す。`/fastship:push-pr` がセルフレビュー (`/simplify` → `/security-review`)・テンプレート適用・Draft → Ready 化までを担うので、本スキルからは結果の PR 番号だけ受け取る。

```bash
PR_NUMBER=$(gh pr view --json number -q .number)
```

> `claude-code-review.yml` は Draft では起動しないため、Ready for review であることを必ず確認する。

### 5. 自動レビュー完了の待機（指数バックオフ）

`gh pr view --json reviews,headRefOid` 一発で「最新 HEAD SHA」と「これまでに届いた全レビュー」をまとめて取得する。間隔は 30 → 60 → 120 → 240 → 300 秒（上限 5 分）で指数バックオフし、累計 30 分でタイムアウトする:

```bash
DELAY=30
ELAPSED=0
LIMIT=$((30 * 60))
CI_FAILED=false
while [ "$ELAPSED" -lt "$LIMIT" ]; do
  PAYLOAD=$(gh pr view "$PR_NUMBER" --json reviews,headRefOid,statusCheckRollup)
  HEAD_SHA=$(echo "$PAYLOAD" | jq -r .headRefOid)
  # 注: `gh pr view --json reviews` (GraphQL 経由) では bot の login は `claude` (suffix なし)。
  # 一方 `gh api .../reviews` (REST) では `claude[bot]` (suffix あり) になる。
  # 本ステップは GraphQL を使っているので "claude" が正しい。REST を使う場合は "claude[bot]" に置き換えること。
  LATEST=$(echo "$PAYLOAD" | jq -c \
    '.reviews | map(select(.author.login == "claude")) | sort_by(.submittedAt) | last // empty')
  STATE=$(echo "$LATEST" | jq -r '.state // ""')
  REVIEW_SHA=$(echo "$LATEST" | jq -r '.commit.oid // ""')
  CI_FAILED=$(echo "$PAYLOAD" | jq -r '[.statusCheckRollup[]? | select(.conclusion == "FAILURE")] | length > 0')

  # 現在の HEAD SHA に対するレビューが届いたら確定
  if [ -n "$STATE" ] && [ "$REVIEW_SHA" = "$HEAD_SHA" ]; then
    echo "review_state=$STATE"
    break
  fi

  # CI 失敗を先に検知した場合は、claude-fix-on-fail.yml の発火と並走しないよう
  # /fastship:dev 側でステップ 7 に合流して CI 修正を自分のコミットに取り込む。
  # レビューが未到着なら $STATE は空のままでステップ 6 → 7 (CI 修正のみ) に進む。
  if [ "$CI_FAILED" = "true" ]; then
    echo "ci_failed=true (レビュー未完了でも 7 に合流して CI 修正をまとめる)"
    break
  fi

  sleep "$DELAY"
  ELAPSED=$((ELAPSED + DELAY))
  DELAY=$(( DELAY * 2 > 300 ? 300 : DELAY * 2 ))
done
```

タイムアウトした場合 (= レビューが届かない or 古い SHA のレビューしか無い) は、以下の優先順位で再レビューを発火する:

1. **`<!-- claude-auto-fix:re-review:{sha} -->` マーカー入りの `/review` コメントを投稿** して `claude-code-review.yml` を起動。同一 SHA への重複投稿は無駄なので、過去のマーカー入りコメントを確認して未投稿の場合のみ投稿する:

   ```bash
   ALREADY=$(gh api "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments" --paginate \
     --jq "[.[] | select(.body | contains(\"<!-- claude-auto-fix:re-review:${HEAD_SHA} -->\"))] | length")
   if [ "$ALREADY" -eq 0 ]; then
     gh pr comment "$PR_NUMBER" --body "$(printf '%s\n%s\n' "<!-- claude-auto-fix:re-review:${HEAD_SHA} -->" "/review")"
   fi
   ```

   投稿後、ステップ 5 のポーリングを再開する (DELAY と ELAPSED をリセット)。
2. それでも届かなければ `AskUserQuestion` で「もう少し待つ / 中断 / 人間に引き継ぐ」を確認する。

> 同一ユーザー (人間) の `/review` 連投は concurrency で先行 run を kill するが、**Bot 投稿は別ユーザー扱いなので先行 run を kill しない**。マーカー dedup により無駄な再投稿も防ぐ。

### 6. レビュー結果による分岐

- `STATE == "APPROVED"` かつ `CI_FAILED == "false"` → ステップ 9（完了処理）へ
- `STATE == "CHANGES_REQUESTED"` → ステップ 7（自己修復）へ。`CI_FAILED == "true"` も並走している場合は 7-c で **同じコミットに CI 修正も含める**
- `STATE` が空 (レビュー未到着) かつ `CI_FAILED == "true"` → ステップ 7 に CI 修正のみで合流。7-a / 7-b / 7-d / 7-e はスキップ可、7-c で `gh run view --log-failed` から原因を特定して修正コミット、7-f で Ready 化
- それ以外 (`COMMENTED` 等) → 内容を読み、`[must]` 相当があるなら 7 へ、なければ APPROVED 待ちで 5 に戻る

### 7. CHANGES_REQUESTED の自己修復

#### 7-a. 該当レビューのコメントだけ取得

全 PR コメントを `--paginate` で舐めると重いので、ステップ 5 で確定した最新 review にぶら下がるコメントだけ取得する:

```bash
REVIEW_ID=$(echo "$LATEST" | jq -r .id)
gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/reviews/${REVIEW_ID}/comments" \
  > /tmp/pr_inline_comments.json
echo "$LATEST" | jq -r .body > /tmp/pr_review_body.md
```

#### 7-b. 対応方針の決定

レビュー指摘プレフィックスの扱い:

- `[must]` → 必ず修正
- `[imo]` / `[nits]` → 採否を判断、見送る場合は返信で理由を明記
- `[ask]` → インライン返信で回答
- プレフィックスなし → 文面から重大度を判断

#### 7-c. 修正コミット

修正対象ファイルを **明示的に指定** してステージし（`git add -A` は使わない）、CLAUDE.md の規約どおりビルド・テストを通してからコミット・push する:

```bash
git add path/to/changed_file_1 path/to/changed_file_2
git commit -m "fix: review #${REVIEW_ID} の指摘に対応"
# upstream はステップ 4 の /fastship:push-pr で初回 push 時に設定済みのため -u は不要。
# 万一未設定で失敗したら `git push -u origin HEAD` で再試行する。
git push
```

#### 7-d. インラインコメントへの返信

`[must]` インラインは **複数件あるのが通常** なので、ステップ 7-a で取得した JSON から `[must]` を含むコメント ID を抽出してループで全件返信する。**対応した COMMENT_ID は配列に控えておき、次の 7-e で resolve に使う**:

```bash
: > /tmp/responded_comment_ids.txt  # 再実行時に前回分の ID が残らないよう初期化
jq -r '.[] | select(.body | startswith("[must]")) | .id' /tmp/pr_inline_comments.json \
  | while read -r comment_id; do
      # body は事前に対応内容と紐付けて準備しておくこと (ID と返信内容のマップを管理)
      gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/comments/${comment_id}/replies" \
        --method POST \
        -f body="対応しました。{この comment_id への対応内容 1 行}"
      echo "$comment_id" >> /tmp/responded_comment_ids.txt
    done
```

> パイプ越しの `while` は subshell で動くため、配列変数では親スコープに ID が残らない。中継はファイル経由で行うこと。

返信文は **対応内容を簡潔に**。「対応しました」だけでは不十分。`[ask]` / 見送った `[imo]` `[nits]` にも返信する (採否の理由を明記)。これらの ID も `/tmp/responded_comment_ids.txt` に追記する。

#### 7-e. 対応した会話を Resolve conversation する

PR 上で「未対応指摘の数」を一目で把握できるようにするため、返信した thread を GraphQL で resolve する。REST のコメント ID と GraphQL の thread ID のマッピングを取り、対応済み ID だけ resolve:

```bash
# thread 一覧 (commentId, threadId) を取得（owner/name はカレントリポジトリから解決）
OWNER=$(gh repo view --json owner -q .owner.login)
REPO=$(gh repo view --json name -q .name)
gh api graphql -f query="
{
  repository(owner: \"${OWNER}\", name: \"${REPO}\") {
    pullRequest(number: ${PR_NUMBER}) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 1) { nodes { databaseId } }
        }
      }
    }
  }
}" --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | "\(.comments.nodes[0].databaseId) \(.id)"' > /tmp/thread_map.txt

while read -r comment_id; do
  thread_id=$(awk -v cid="$comment_id" '$1 == cid {print $2}' /tmp/thread_map.txt)
  [ -z "$thread_id" ] && continue
  gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) { thread { isResolved } }
  }' -f threadId="$thread_id" >/dev/null
done < /tmp/responded_comment_ids.txt
```

> 完了条件: `[must]` インライン全件に返信が付き、対応した thread がすべて resolve されるまで作業完了とみなさない (`claude-code-review.yml` の依頼コメント本文の制約と整合)。

#### 7-f. Draft → Ready に戻す

`claude-code-review.yml` は CHANGES_REQUESTED で PR を Draft に戻す仕様。修正 push 後は必ず Ready に戻す:

```bash
gh pr ready "$PR_NUMBER"
```

→ ステップ 5 に戻る。

### 8. ループ上限

ステップ 5–7 のループは **最大 3 周** まで。3 周目でも CHANGES_REQUESTED が継続する場合、または「同一指摘が 2 周連続で残っている」場合は即エスカレーションする:

1. これまでの周回でどの指摘に対応したか・残った指摘は何かを PR にサマリコメントとして残す
2. `AskUserQuestion` で「人間に引き継ぐ / 別アプローチで再挑戦 / そのまま強行マージ依頼」を確認

### 9. 完了処理

APPROVED が出たら以下を実行:

1. PR にマージ準備完了の通知コメントを投稿（`@claude` を含めない。下記「Bot ループ防止」参照）:

   ```bash
   gh pr comment "$PR_NUMBER" --body "自動レビューで APPROVED が出ました。マージ可能です。"
   ```

2. PR 番号と URL を最終出力としてユーザーに返す（claude.ai/code のセッション結果としてスマホに通知される）

**自動マージはしない**。マージは人間がスマホの GitHub アプリから行う。

## 注意事項

- **`/review` の投稿はマーカー付きで dedup する**: 再レビューは原則「修正 push → Ready 化」の自然なトリガーで起こす。それでも届かない場合のみ、ステップ 5 の手順に従い `<!-- claude-auto-fix:re-review:{sha} -->` マーカー入りで投稿する。マーカー無しの素の `/review` を Bot から連投すると先行 run を kill する可能性があるため避ける
- **Bot ループ防止**: PR コメント本文に `@claude` を含めない。`claude.yml` は本文に `@claude` を含むコメントで起動するため、自分の投稿で自分自身を再起動させ得る
- **同一 SHA の再レビューは発生しない**: 修正 push をせずに `gh pr ready` だけしてもレビューは走らない（既に APPROVED/CHANGES_REQUESTED 済みの SHA は `claude-code-review.yml` 側で skip）
- **`claude-auto-fix:` 系ワークフローとの二重起動**: 本スキル実行中に CI 失敗 (`claude-fix-on-fail.yml`) または CHANGES_REQUESTED (`claude-code-review.yml`) が発生すると、それぞれが別途 `@claude` 自動修復依頼コメントを投稿し、別エージェントが同 PR に修正コミットを重ねる可能性がある。これを避けるため、本スキルでは **ステップ 5 のループ内で `gh pr view --json statusCheckRollup` も確認し、CI 失敗があれば自分のコミットに修正をまとめる**（両 yml は同一 SHA への重複依頼を抑止する仕様だが、新しい SHA を push したタイミングで両者が並走するリスクは残る）。スマホからセッションを切った後は、`claude-auto-fix:` 系の自走に任せる前提
