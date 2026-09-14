---
name: dev
description: GitHub Issue を引数に受け取り、実装 → PR 作成 → `/code-review` でレビュー起動 → `[must]` の自己修復 → 指摘ゼロまで一気通貫で進めるスキル。Claude Code Web (claude.ai/code) からスマホで起動して放置運用するためのもの。使い方 → /indiehacker:dev {GitHub Issue 番号}
---

# Issue 実装からマージ可能までの自走

claude.ai/code から `/indiehacker:dev {Issue 番号}` で起動し、実装 → `/indiehacker:push-pr` → `/code-review` でレビューを起動 → `[must]` を自己修復 → 指摘ゼロまで持っていくためのスキル。スマホ運用を前提に、最後の Approve & Merge だけ人間に委ねる。

## 依存ワークフロー / 規約

このスキルは以下に依存している。挙動が変わった場合はここを更新する:

- **PR コメント `/code-review`** — `theindiehacker/github-workflows` の reusable workflow を呼ぶ caller ワークフローを起動し、指摘を**該当行へのインラインコメント**として投稿する。**コメント完全一致でのみ起動**し、PR レビューを APPROVED / CHANGES_REQUESTED として submit することはない（`/code-review fable` で Fable 5.1 を使う）
- このプラグインの push-pr スキル（`/indiehacker:push-pr`） — PR 作成・更新のセルフレビューと Ready 化までを担う
- プロジェクトの `CLAUDE.md` — 完了条件（テスト・Lint の通過、フックを `--no-verify` で迂回しない）とレビュー指摘プレフィックス規約（`[must]` / `[imo]` / `[nits]` / `[ask]`）

> レビューワークフローが未導入のリポジトリでは `/code-review` は起動しない。その場合は `/indiehacker:install-review-workflow` での導入を案内し、ステップ 4（PR 作成）までで完了として報告する。

## 手順

### 1. Issue の取得とスコープ確認

```bash
ISSUE_NUMBER={引数}
gh issue view "$ISSUE_NUMBER" --json title,body,labels
```

- ユーザーストーリー / 達成条件を読み、不明点があれば `AskUserQuestion` で確認する（claude.ai/code 経由なら通知が飛ぶ）
- `backlog` ラベルが付いている場合は **「先に `/indiehacker:refine` で Todo に分解した方がよくないか」を確認** する。Backlog をそのまま実装すると粒度が大きすぎることが多い

### 2. 作業ブランチを作成

```bash
git checkout main && git pull
git checkout -b "feature/issue-${ISSUE_NUMBER}"
```

ブランチが既に存在する場合は `feature/issue-${ISSUE_NUMBER}-2` など連番でフォールバックする。

### 2.5. 失敗するテストを先に書く（Red）

Issue に `🧪 テスト方針`（入力 → 期待値）があり、リポジトリに受け入れテストの置き場がある場合、実装前に `Agent` ツールで `subagent_type: "indiehacker:tdd"` を呼び、テストスケルトンを生成させる。Issue 番号と達成基準・テスト方針を渡す。

- 生成されたテストが**失敗すること**を確認してから実装に入る（通ってしまうなら、テストが要件を検証できていない）。
- テスト方針が無い Issue（ドキュメント修正・設定変更など）や、受け入れテストの仕組みが無いリポジトリではスキップする。

### 3. 実装

`Skill` ツールから `/feature-dev`（`feature-dev@claude-plugins-official`。**未インストールなら、そのまま自分で実装する** — このスキルの必須依存ではない）を呼び出して実装する。完了条件はリポジトリの CLAUDE.md に従う（lint / テストの通過、フックを `--no-verify` で迂回しない 等。`task style:check` / `task dev:test` は Taskfile があるリポジトリの例）。

> `/feature-dev` は汎用プラグインで DDD 非対応。会社標準の規約（このプラグイン同梱の `rules/**`）とプロジェクトの `.claude/rules/**` は、このプラグインの rules-guard フック（PreToolUse: Read|Edit|Write）が対象パスに触れた初回に要点を注入するが、**実装対象パスにマッチするルールは書き始める前に全文を Read** する。実装をサブエージェント（`Agent` ツール）にファンアウトする場合は rules の自動ロードが保証されないため、該当ルールファイルのパスを prompt に明記して必ず Read させる。Issue 説明欄に `/indiehacker:design` のドメインモデル設計書（`<!-- domain-model-design -->` マーカー区間）があれば、その集約境界・不変条件・振る舞いに厳密に従う。

### 3.5. ドメインモデル鑑定ゲート（PR 前）

`backend/src/**/domain/**` または `**/application/**` に変更がある場合、PR を作る**前に** `Agent` ツールで `subagent_type: "indiehacker:domain-model-reviewer"` を呼び、DDD の意味論的スメル（貧血ドメイン・集約境界越え Tx・primitive obsession・ロジック漏れ・用語ドリフト）を鑑定する。Issue 番号を渡し、設計書と突き合わせさせる。

**このとき DDD 規約の絶対パスを prompt に列挙して渡す。** プラグインはプロジェクト外に install されるためサブエージェントは `Glob` では規約を見つけられず、渡さないと要約だけで鑑定してしまう。パスが手元に無ければ、次で列挙できる:

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ ! -d "${PLUGIN_ROOT:-/nonexistent}/rules" ]; then
  PLUGIN_ROOT=$(find "$HOME/.claude/plugins" "${CLAUDE_PROJECT_DIR:-.}/.claude/plugins" \
    -maxdepth 6 -type d -path '*/indiehacker/*' -name rules 2>/dev/null | head -1)
  PLUGIN_ROOT="${PLUGIN_ROOT%/rules}"
fi
ls "$PLUGIN_ROOT"/rules/backend/src/domain/model/*.md "$PLUGIN_ROOT"/rules/backend/src/application/application.md
```

- `PASS`（`[must]` 無し）→ ステップ 4 へ。
- `CHANGES_REQUESTED`（`[must]` あり）→ **PR を作る前に自分で修正**する。集約メソッドへのロジック引き上げ・VO 化・イベント化など、鑑定士の直し方に従い、`task style:check` / `task dev:test` を通してから再度鑑定 → `PASS` になったらステップ 4 へ。
- 鑑定→修正→再鑑定は **最大 2 周** まで。2 周目でも同じ `[must]` が残る場合は設計自体に問題がある可能性が高いので、`AskUserQuestion` で「設計書に戻る（/indiehacker:design やり直し）/ 指摘を見送って PR を出す / 人間に引き継ぐ」を確認する（ステップ 8 と同型のエスカレーション）。
- ドメイン層に変更が無い純粋なインフラ/設定変更なら本ステップはスキップ可。

> 目的は「bot/人間レビューや自分の手戻りが起きる前に、DDD 崩れをローカルで潰す」こと。ここを通してから PR を出すことで、ステップ 5–7 のレビューループでの DDD 指摘を減らす。

### 4. PR 作成（Ready for review まで）

`Skill` ツールから `/indiehacker:push-pr` を呼び出す。`/indiehacker:push-pr` がセルフレビュー (`/simplify`)・テンプレート適用・Draft → Ready 化までを担うので、本スキルからは結果の PR 番号だけ受け取る。

```bash
PR_NUMBER=$(gh pr view --json number -q .number)
```

> Draft のままでもレビューは起動するが、レビュー結果に対して人間がすぐ反応できるよう Ready for review にしてから次に進む。

### 5. レビューの起動と完了待機（指数バックオフ）

レビューは **PR に `/code-review` とコメントして起動する**（コメント完全一致。前後に文字を足すと起動しない）。
同一 SHA に対する二重起動を避けるため、その SHA でまだ起動していない場合だけ投稿する:

```bash
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid -q .headRefOid)

# この SHA に対する run が既にあるか確認してから投稿する
RUNS=$(gh run list --workflow=claude-review.yml --json headSha,status,conclusion,databaseId --limit 50)
if [ "$(echo "$RUNS" | jq -r --arg sha "$HEAD_SHA" '[.[] | select(.headSha == $sha)] | length')" -eq 0 ]; then
  gh pr comment "$PR_NUMBER" --body "/code-review"
fi
```

投稿後、**その SHA に対する run の完了**を待つ。間隔は 30 → 60 → 120 → 240 → 300 秒（上限 5 分）で指数バックオフし、累計 30 分でタイムアウトする:

```bash
DELAY=30
ELAPSED=0
LIMIT=$((30 * 60))
REVIEW_DONE=false
CI_FAILED=false
while [ "$ELAPSED" -lt "$LIMIT" ]; do
  RUNS=$(gh run list --workflow=claude-review.yml --json headSha,status,conclusion --limit 50)
  REVIEW_DONE=$(echo "$RUNS" | jq -r --arg sha "$HEAD_SHA" \
    '[.[] | select(.headSha == $sha and .status == "completed")] | length > 0')
  CI_FAILED=$(gh pr view "$PR_NUMBER" --json statusCheckRollup \
    --jq '[.statusCheckRollup[]? | select(.conclusion == "FAILURE")] | length > 0')

  # レビュー完了、または CI 失敗を検知したらステップ 6 へ
  if [ "$REVIEW_DONE" = "true" ] || [ "$CI_FAILED" = "true" ]; then
    echo "review_done=$REVIEW_DONE ci_failed=$CI_FAILED"
    break
  fi

  sleep "$DELAY"
  ELAPSED=$((ELAPSED + DELAY))
  DELAY=$(( DELAY * 2 > 300 ? 300 : DELAY * 2 ))
done
```

タイムアウトした場合（run が作られない / 完了しない）は、以下の順で切り分ける:

1. `gh run list --workflow=claude-review.yml --limit 5` で run 自体が作られているか確認する。
   **0 件なら caller ワークフローが未導入か、まだ main にマージされていない**
   （`issue_comment` は常にデフォルトブランチ版の定義で実行される）。
   `/indiehacker:install-review-workflow` での導入を案内して終了する。
2. run はあるが失敗している場合は `gh run view <id> --log-failed` で原因を読む
   （org シークレット未登録・Claude GitHub App 未 install などの前提不足が多い）。
3. それ以外は `AskUserQuestion` で「もう少し待つ / 中断 / 人間に引き継ぐ」を確認する。

### 6. レビュー結果による分岐

レビューは **PR レビュー（APPROVED / CHANGES_REQUESTED）としては submit されず、該当行へのインラインコメントとして投稿される**。
そのため分岐は review state ではなく、**現 HEAD SHA に対する未 resolve の `[must]` 件数**で行う:

```bash
OWNER=$(gh repo view --json owner -q .owner.login)
REPO=$(gh repo view --json name -q .name)

# 未 resolve の thread に紐づくコメントだけを対象にする
gh api graphql -f query="
{
  repository(owner: \"${OWNER}\", name: \"${REPO}\") {
    pullRequest(number: ${PR_NUMBER}) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 1) { nodes { databaseId body } }
        }
      }
    }
  }
}" > /tmp/pr_threads.json

MUST_COUNT=$(jq '[.data.repository.pullRequest.reviewThreads.nodes[]
  | select(.isResolved == false)
  | .comments.nodes[0] | select(.body | startswith("[must]"))] | length' /tmp/pr_threads.json)
```

- `MUST_COUNT == 0` かつ `CI_FAILED == "false"` → ステップ 9（完了処理）へ
- `MUST_COUNT > 0` → ステップ 7（自己修復）へ。`CI_FAILED == "true"` も並走している場合は 7-c で **同じコミットに CI 修正も含める**
- `MUST_COUNT == 0` かつ `CI_FAILED == "true"` → ステップ 7 に CI 修正のみで合流。7-a / 7-b / 7-d / 7-e はスキップ可、7-c で `gh run view --log-failed` から原因を特定して修正コミット
- `[must]` 以外（`[imo]` / `[nits]` / `[ask]`）しか無い場合も 7 へ。採否を判断し、全件に返信する

### 7. `[must]` 指摘の自己修復

#### 7-a. 対象コメントの取得

レビューは PR レビューとして submit されないため、`reviews/{id}/comments` ではなく
**ステップ 6 で取得した未 resolve thread の先頭コメント**（＝指摘本体。返信は含めない）を対象にする:

```bash
jq '[.data.repository.pullRequest.reviewThreads.nodes[]
  | select(.isResolved == false) | .comments.nodes[0]]' /tmp/pr_threads.json \
  > /tmp/pr_inline_comments.json
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
git commit -m "fix: レビュー指摘に対応"
# upstream はステップ 4 の /indiehacker:push-pr で初回 push 時に設定済みのため -u は不要。
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

> 完了条件: `[must]` インライン全件に返信が付き、対応した thread がすべて resolve されるまで作業完了とみなさない。ステップ 6 の `MUST_COUNT` は未 resolve thread を数えるため、**resolve を怠るとループが終わらない**。

#### 7-f. 再レビューの起動

修正を push すると HEAD SHA が変わる。新しい SHA に対してレビューは**自動では走らない**ので、
ステップ 5 に戻って `HEAD_SHA` を取り直し、`/code-review` を再投稿する。

→ ステップ 5 に戻る。

### 8. ループ上限

ステップ 5–7 のループは **最大 3 周** まで。3 周目でも `[must]` が残る場合、または「同一指摘が 2 周連続で残っている」場合は即エスカレーションする:

1. これまでの周回でどの指摘に対応したか・残った指摘は何かを PR にサマリコメントとして残す
2. `AskUserQuestion` で「人間に引き継ぐ / 別アプローチで再挑戦 / そのまま強行マージ依頼」を確認

### 9. 完了処理

**現 HEAD SHA でレビュー run が完了し、未 resolve の `[must]` が 0 件** になったら以下を実行:

1. PR にマージ準備完了の通知コメントを投稿:

   ```bash
   gh pr comment "$PR_NUMBER" --body "レビューの [must] 指摘はすべて対応済みです。マージ可能です。"
   ```

2. PR 番号と URL を最終出力としてユーザーに返す（claude.ai/code のセッション結果としてスマホに通知される）

**自動マージはしない**。マージは人間がスマホの GitHub アプリから行う。

## 注意事項

- **レビューはコメント完全一致でのみ起動する**: `/code-review`・`/code-review fable`・`/security-review` の 3 つだけ。前後に文字を足した `/code-review お願いします` のようなコメントでは起動しない
- **同一 SHA に `/code-review` を連投しない**: 先行 run が concurrency で kill される。ステップ 5 のとおり、その SHA の run が無い場合だけ投稿する
- **レビューは自動では走らない**: 修正 push で HEAD SHA が変わっても、`/code-review` を再投稿するまでレビューは起動しない（ステップ 7-f）
- **resolve を怠るとループが終わらない**: ステップ 6 の `MUST_COUNT` は未 resolve thread を数えるため、対応した thread は 7-e で必ず resolve する
- **起動できる条件**: PR が open で、コメント投稿者が OWNER / MEMBER / COLLABORATOR かつ Bot でないこと。Bot アカウントから投稿しても起動しない
- **セキュリティレビューは別コマンド**: 認証認可・決済・`.github/workflows/**` などに触れる変更は `/indiehacker:push-pr` の判断に従い `/security-review` も依頼する
