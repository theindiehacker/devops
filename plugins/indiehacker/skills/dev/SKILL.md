---
name: dev
description: GitHub Issue を引数に受け取り、実装 → PR 作成 → `/code-review` でレビュー起動 → `[must]` の自己修復 → 指摘ゼロまで一気通貫で進めるスキル。Claude Code Web (claude.ai/code) からスマホで起動して放置運用するためのもの。使い方 → /indiehacker:dev {GitHub Issue 番号}
---

# Issue 実装からマージ可能までの自走

claude.ai/code から `/indiehacker:dev {Issue 番号}` で起動し、実装 → `/indiehacker:push-pr` → `/code-review` でレビューを起動 → `[must]` を自己修復 → 指摘ゼロまで持っていくためのスキル。スマホ運用を前提に、最後の Approve & Merge だけ人間に委ねる。

## 依存ワークフロー / 規約

このスキルは以下に依存している。挙動が変わった場合はここを更新する:

- **PR コメント `/code-review`** — `github-workflows` の reusable workflow を呼ぶ caller ワークフロー（`/indiehacker:install-review-workflow` が導入）を起動し、指摘を**該当行へのインラインコメント**として投稿する。**コメント完全一致でのみ起動**し、PR レビューを APPROVED / CHANGES_REQUESTED として submit することはない（`/code-review fable` で Fable 5.1 を使う）
- このプラグインの push-pr スキル（`/indiehacker:push-pr`） — PR 作成・更新のセルフレビューと Ready 化までを担う
- プロジェクトの `CLAUDE.md` — 完了条件（テスト・Lint の通過、フックを `--no-verify` で迂回しない）とレビュー指摘プレフィックス規約（`[must]` / `[imo]` / `[nits]` / `[ask]`）

> レビューワークフローが未導入のリポジトリでは `/code-review` は起動しない。その場合は `/indiehacker:install-review-workflow` での導入を案内し、ステップ 4（PR 作成）までで完了として報告する。

## 手順

### 1. Issue の取得とスコープ確認

```bash
ISSUE_NUMBER={引数}
# gh issue view --json は GraphQL のため使わない (claude.ai/code のセッションでは 403)
gh api "repos/{owner}/{repo}/issues/${ISSUE_NUMBER}" \
  --jq '{title, body, labels:[.labels[].name]}'
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
# 右辺の表記はスキル読み込み時に Claude Code がプラグインの実パスへ置換する（`:-` などの修飾を付けると置換されない）。
# 置換されなかった場合だけキャッシュを探す。旧バージョンが残っていることがあるので最新版を選ぶ
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
if [ ! -d "${PLUGIN_ROOT:-/nonexistent}/rules" ]; then
  PLUGIN_ROOT=$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache" -mindepth 4 -maxdepth 4 \
    -type d -path '*/indiehacker/*' -name rules 2>/dev/null | sort -V | tail -1)
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
# gh pr view --json は GraphQL のため使わない。REST でブランチから PR 番号を引く
BRANCH=$(git branch --show-current)
OWNER=$(gh api 'repos/{owner}/{repo}' --jq .owner.login)
PR_NUMBER=$(gh api "repos/{owner}/{repo}/pulls?head=${OWNER}:${BRANCH}" --jq '.[0].number')
```

> Draft のままでもレビューは起動するが、レビュー結果に対して人間がすぐ反応できるよう Ready for review にしてから次に進む。

### 5. レビューの起動と完了待機（指数バックオフ）

レビューは **PR に `/code-review` とコメントして起動する**（コメント完全一致。前後に文字を足すと起動しない）。

> **run は SHA では特定できない。** `issue_comment` で起動した run の `headSha` / `headBranch` は
> **デフォルトブランチの HEAD** になり、PR の HEAD SHA とは一致しない（実測確認済み）。
> また caller はリポジトリ内の**すべての**コメントで起動し、無関係なコメントの run は job が `skipped` で終わる。
> そのため run は「依頼コメントの投稿時刻以降に作られた」「`display_title` が PR タイトルと一致する」
> 「`code-review` job が実際に動いた（`in_progress`、または `skipped` 以外で `completed`）」の 3 条件で特定する。

**必ず 1 回の `Bash` 呼び出しで実行する**（Bash ツールはシェル変数を呼び出し間で保持しない）:

```bash
HEAD_SHA=$(gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}" --jq .head.sha)
PR_TITLE=$(gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}" --jq .title)
HEAD_DATE=$(gh api "repos/{owner}/{repo}/commits/${HEAD_SHA}" --jq .commit.committer.date)
ME=$(gh api user --jq .login)

# 1) HEAD コミット以降に自分が /code-review を投稿済みなら再投稿しない（連投すると先行 run が concurrency で kill される）。
#    `--paginate` は使わないこと。GitHub の Link ヘッダは numeric-ID パス
#    (repositories/{id}/...) を返すが、claude.ai/code のプロキシはそれを拒否するため
#    2 ページ目でエラー JSON が混ざり、jq のパースごと壊れる（実測確認済み）。
#    ページ番号を明示して回す
fetch_all() {  # $1 = クエリ付きパス (per_page/page は付けない)
  local page=1 chunk n
  : > /tmp/gh_page.jsonl
  while :; do
    chunk=$(gh api "$1&per_page=100&page=${page}")
    n=$(printf '%s' "$chunk" | jq 'length')
    printf '%s' "$chunk" | jq -c '.[]' >> /tmp/gh_page.jsonl
    [ "$n" -lt 100 ] && break
    page=$((page + 1))
  done
  jq -s '.' /tmp/gh_page.jsonl
}

REQUESTED_AT=$(fetch_all "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments?since=${HEAD_DATE}" \
  | jq -r --arg me "$ME" --arg since "$HEAD_DATE" \
      '[.[] | select(.user.login == $me and .body == "/code-review" and .created_at >= $since) | .created_at] | last // empty')
if [ -z "$REQUESTED_AT" ]; then
  # gh pr comment は使わない。issue comments の REST に投稿する
  jq -n '{body:"/code-review"}' > /tmp/review_request.json
  REQUESTED_AT=$(gh api --method POST "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments" \
    --input /tmp/review_request.json --jq .created_at)
fi
echo "HEAD_SHA=$HEAD_SHA REQUESTED_AT=$REQUESTED_AT"

# 2) 依頼に対応する run を特定し、code-review job の完了を待つ。間隔は 30 → 60 → 120 → 240 → 300 秒
#    （上限 5 分）で指数バックオフし、累計 30 分でタイムアウトする。
DELAY=30
ELAPSED=0
LIMIT=$((30 * 60))
RUN_ID=""
REVIEW_DONE=false
REVIEW_CONCLUSION=""
CI_FAILED=false
while [ "$ELAPSED" -lt "$LIMIT" ]; do
  if [ -z "$RUN_ID" ]; then
    # run は新しい順に並ぶ。同じ PR への依頼が複数あれば、concurrency で生き残る最新の run を採る
    for id in $(gh api "repos/{owner}/{repo}/actions/workflows/claude-review.yml/runs?event=issue_comment&created=%3E%3D${REQUESTED_AT}&per_page=100" \
                  | jq -r --arg t "$PR_TITLE" '.workflow_runs[] | select(.display_title == $t) | .id'); do
      if [ "$(gh api "repos/{owner}/{repo}/actions/runs/${id}/jobs" \
              | jq '[.jobs[] | select((.name | startswith("code-review")) and (.status == "in_progress" or (.status == "completed" and .conclusion != "skipped")))] | length > 0')" = "true" ]; then
        RUN_ID=$id
        break
      fi
    done
  fi

  if [ -n "$RUN_ID" ]; then
    JOB=$(gh api "repos/{owner}/{repo}/actions/runs/${RUN_ID}/jobs" \
      | jq -r '[.jobs[] | select(.name | startswith("code-review"))][0] | "\(.status) \(.conclusion // "")"')
    if [ "${JOB%% *}" = "completed" ]; then
      REVIEW_DONE=true
      REVIEW_CONCLUSION=${JOB#* }
    fi
  fi
  CI_FAILED=$(gh api "repos/{owner}/{repo}/commits/${HEAD_SHA}/check-runs?per_page=100" \
    --jq '[.check_runs[]? | select(.conclusion == "failure")] | length > 0')

  # レビュー完了、または CI 失敗を検知したらステップ 6 へ
  if [ "$REVIEW_DONE" = "true" ] || [ "$CI_FAILED" = "true" ]; then
    break
  fi

  sleep "$DELAY"
  ELAPSED=$((ELAPSED + DELAY))
  DELAY=$(( DELAY * 2 > 300 ? 300 : DELAY * 2 ))
done
echo "run_id=${RUN_ID:-<未検出>} review_done=$REVIEW_DONE review_conclusion=${REVIEW_CONCLUSION:-<未完了>} ci_failed=$CI_FAILED"
```

タイムアウトした場合、または `review_conclusion` が `success` 以外の場合は、以下の順で切り分ける:

1. **`run_id` が未検出** → caller ワークフローがデフォルトブランチにあるか確認する:

   ```bash
   gh api "repos/{owner}/{repo}/actions/workflows/claude-review.yml" --jq .state
   ```

   404 なら **caller ワークフローが未導入か、まだデフォルトブランチにマージされていない**
   （`issue_comment` は常にデフォルトブランチ版の定義で実行される）。
   `/indiehacker:install-review-workflow` での導入を案内して終了する。
   存在するのに見つからない場合は、依頼に対応する run の `code-review` job が `skipped` になっている（起動条件を満たしていない）。
   PR が open か、投稿者が OWNER / MEMBER / COLLABORATOR かつ Bot でないかを確認する。
2. **`review_conclusion` が `success` 以外** → `gh run view <run_id> --log-failed` で原因を読む
   （org シークレット未登録・Claude GitHub App 未 install などの前提不足が多い。
   `cancelled` は同じ PR への後続の `/code-review` で先行 run が kill された可能性がある）。
3. それ以外は `AskUserQuestion` で「もう少し待つ / 中断 / 人間に引き継ぐ」を確認する。

### 6. レビュー結果による分岐

レビューは **PR レビュー（APPROVED / CHANGES_REQUESTED）としては submit されず、該当行へのインラインコメントとして投稿される**。
そのため分岐は review state ではなく、**現 HEAD SHA に対する未 resolve の `[must]` 件数**で行う:

```bash
# 1) スレッド一覧を取得する。thread の resolve 状態は REST に無いため、
#    claude.ai/code では CCR 専用ルート、ローカル CLI では GraphQL を使う
#    （claude.ai/code では GraphQL が 403、ローカル CLI では CCR ルートが 404。いずれも実測確認済み）。
if ! gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/ccr/review_threads" > /tmp/review_threads.json 2>/dev/null; then
  # CCR ルートと同じ形 ({resolved, comment_ids}) にそろえる。thread_id はステップ 7-e の resolve で使う
  gh api graphql -F owner='{owner}' -F name='{repo}' -F number="$PR_NUMBER" -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          reviewThreads(first: 100) {
            nodes { id isResolved comments(first: 1) { nodes { databaseId } } }
          }
        }
      }
    }' --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | {thread_id: .id, resolved: .isResolved, comment_ids: [.comments.nodes[].databaseId]}]' \
    > /tmp/review_threads.json || { echo "REVIEW_THREADS_UNAVAILABLE"; exit 1; }
fi

# 未 resolve スレッドの「先頭コメント ID」を集める (指摘本体。返信は含めない)
jq '[.[] | select(.resolved == false) | .comment_ids[0]]' /tmp/review_threads.json > /tmp/open_thread_ids.json

# 2) インラインコメント本文を引いて突き合わせる
#    `--paginate` は claude.ai/code のプロキシで 2 ページ目が壊れるため使わない（ステップ 5 と同じ理由）
page=1
: > /tmp/gh_page.jsonl
while :; do
  chunk=$(gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/comments?per_page=100&page=${page}")
  n=$(printf '%s' "$chunk" | jq 'length')
  printf '%s' "$chunk" | jq -c '.[]' >> /tmp/gh_page.jsonl
  [ "$n" -lt 100 ] && break
  page=$((page + 1))
done
jq -s '.' /tmp/gh_page.jsonl > /tmp/pr_all_comments.json

jq --slurpfile ids /tmp/open_thread_ids.json \
  '[.[] | select(.id as $i | $ids[0] | index($i))]' /tmp/pr_all_comments.json \
  > /tmp/pr_inline_comments.json

MUST_COUNT=$(jq '[.[] | select(.body | startswith("[must]"))] | length' /tmp/pr_inline_comments.json)
echo "MUST_COUNT=$MUST_COUNT"
```

- `REVIEW_CONCLUSION` が `success` 以外（レビュー run が失敗・キャンセル）→ 指摘は数えず、ステップ 5 の切り分け 2 へ
- `MUST_COUNT == 0` かつ `CI_FAILED == "false"` → ステップ 9（完了処理）へ
- `MUST_COUNT > 0` → ステップ 7（自己修復）へ。`CI_FAILED == "true"` も並走している場合は 7-c で **同じコミットに CI 修正も含める**
- `MUST_COUNT == 0` かつ `CI_FAILED == "true"` → ステップ 7 に CI 修正のみで合流。7-a / 7-b / 7-d / 7-e はスキップ可、7-c で `gh run view --log-failed` から原因を特定して修正コミット
- `[must]` 以外（`[imo]` / `[nits]` / `[ask]`）しか無い場合も 7 へ。採否を判断し、全件に返信する

### 7. `[must]` 指摘の自己修復

#### 7-a. 対象コメントの取得

ステップ 6 が `/tmp/pr_inline_comments.json` に**未 resolve スレッドの先頭コメント**（＝指摘本体。返信は含めない）を
書き出しているので、それをそのまま使う。追加の取得は不要。

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

PR 上で「未対応指摘の数」を一目で把握できるようにするため、返信した thread を resolve する。
resolve は REST に無い。claude.ai/code では GraphQL の `resolveReviewThread` がブロックされるため CCR 専用ルート
（thread ID ではなく**コメント ID** を渡す）を使い、CCR ルートが無いローカル CLI では GraphQL にフォールバックする:

```bash
while read -r comment_id; do
  [ -z "$comment_id" ] && continue
  gh api --method POST \
    "repos/{owner}/{repo}/pulls/${PR_NUMBER}/ccr/comments/${comment_id}/resolve" > /dev/null 2>&1 && continue
  # ローカル CLI: ステップ 6 が GraphQL で取得した /tmp/review_threads.json の thread_id で resolve する
  thread_id=$(jq -r --argjson cid "$comment_id" \
    '.[] | select(.comment_ids[0] == $cid) | .thread_id // empty' /tmp/review_threads.json)
  if [ -n "$thread_id" ] && gh api graphql -F id="$thread_id" \
       -f query='mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }' > /dev/null; then
    continue
  fi
  echo "RESOLVE_FAILED $comment_id"
done < /tmp/responded_comment_ids.txt
```

`RESOLVE_FAILED` が出た場合は黙って進まず、どのコメントを resolve できなかったかを報告する。

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
   jq -n --arg body "レビューの [must] 指摘はすべて対応済みです。マージ可能です。" '{body:$body}' \
     > /tmp/done_comment.json
   gh api --method POST "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments" \
     --input /tmp/done_comment.json > /dev/null
   ```

2. PR 番号と URL を最終出力としてユーザーに返す（claude.ai/code のセッション結果としてスマホに通知される）

**自動マージはしない**。マージは人間がスマホの GitHub アプリから行う。

## 注意事項

- **レビューはコメント完全一致でのみ起動する**: `/code-review`・`/code-review fable`・`/security-review` の 3 つだけ。前後に文字を足した `/code-review お願いします` のようなコメントでは起動しない
- **同一 SHA に `/code-review` を連投しない**: 先行 run が concurrency で kill される。ステップ 5 のとおり、HEAD コミット以降にまだ依頼していない場合だけ投稿する
- **run を `headSha` で探さない**: `issue_comment` 起動の run はデフォルトブランチの SHA を持つため、PR の HEAD SHA とは一致しない（ステップ 5）
- **レビューは自動では走らない**: 修正 push で HEAD SHA が変わっても、`/code-review` を再投稿するまでレビューは起動しない（ステップ 7-f）
- **resolve を怠るとループが終わらない**: ステップ 6 の `MUST_COUNT` は未 resolve thread を数えるため、対応した thread は 7-e で必ず resolve する
- **起動できる条件**: PR が open で、コメント投稿者が OWNER / MEMBER / COLLABORATOR かつ Bot でないこと。Bot アカウントから投稿しても起動しない
- **セキュリティレビューは別コマンド**: 認証認可・決済・`.github/workflows/**` などに触れる変更は `/indiehacker:push-pr` の判断に従い `/security-review` も依頼する
