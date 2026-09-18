---
name: push-pr
description: PR テンプレートに従って Pull Request を作成・更新するコマンド。PR の新規作成、既存 PR の説明欄更新、Draft から Ready for Review への変更、Diff コメントの投稿、作成/更新後の CI 監視とレビューコメントへの対応・返信を行う。「PR 作成して」「PR 更新して」「Draft 解除して」「レビュー依頼したい」などのリクエストで使用する。
model: sonnet
---

# Pull Request 作成・更新

## 手順

### 1. ベースブランチの特定と変更内容の把握

#### 1-a. ベースブランチの特定

このプロジェクトでは通常 `main` をベースとするが、誤ったベースに PR を出すリスクを下げるため明示的に確定させる:

1. **既存 PR がある場合** はその PR のベースをそのまま使う（運用変更や別ベース運用への切り替えに対する保険）。

   > **`gh pr view --json` を使わないこと。** `number` を除く全フィールドが内部で GraphQL を叩くが、
   > **claude.ai/code のセッションでは GraphQL が 403 でブロックされる**（実測確認済み）。REST (`gh api`) を使う
   > （REST はローカル CLI でもそのまま動く）。
   > `repos/{owner}/{repo}` のプレースホルダは gh が git remote からローカル解決する（GraphQL 不要）。

   **必ず 1 回の `Bash` 呼び出しで実行する**（Bash ツールはシェル変数を呼び出し間で保持しない）:

   ```bash
   BRANCH=$(git branch --show-current)
   OWNER=$(gh api 'repos/{owner}/{repo}' --jq .owner.login)
   # PR 未作成なら PR_NUMBER は空文字になる（非ゼロ終了しない）
   PR_NUMBER=$(gh api "repos/{owner}/{repo}/pulls?head=${OWNER}:${BRANCH}&state=open" --jq '.[0].number // empty')

   BASE_BRANCH=""
   if [ -n "$PR_NUMBER" ]; then
     BASE_BRANCH=$(gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}" --jq .base.ref)
   fi
   echo "PR_NUMBER=${PR_NUMBER:-<未作成>} BASE_BRANCH=${BASE_BRANCH:-<未確定>} OWNER=$OWNER BRANCH=$BRANCH"
   ```

   出力した `PR_NUMBER` / `BASE_BRANCH` / `OWNER` は以降のステップでリテラルとして埋めて使う。

2. 取得できなければ `main` を使う:
   ```bash
   BASE_BRANCH="${BASE_BRANCH:-main}"
   ```

3. HEAD が `$BASE_BRANCH` の祖先関係にない、または明らかに別ブランチから派生していると気付いた場合は、`AskUserQuestion` でユーザーに確認する。誤ったベースに PR を出すリスクは、1 度聞くコストよりはるかに大きい。

#### 1-b. 差分の確認

確定した `$BASE_BRANCH` を使って変更内容を把握する:
- `git status` で変更ファイル一覧を確認
- `git diff "$BASE_BRANCH"...HEAD` でベースからの全変更差分を確認
- `git log "$BASE_BRANCH"..HEAD --oneline` でコミット履歴を確認

#### 1-c. セルフレビュー（必須）

PR 作成・更新は「実装が一通り完了したタイミング」と等価なので、ここで品質ゲートを通す。

**セキュリティレビューは CI に委譲する（ローカルでは実行しない）**: PR に `/security-review` とコメントすると
CI（`/dev:setup` が導入する caller ワークフロー）が
claude-opus-5・フレッシュコンテキストで `/security-review` を実行する。
ローカルで実行しないのは、(1) 長いセッション履歴ごと課金される、(2) 本スキルの実行モデル（frontmatter の
`model`）でセキュリティ判断を行うことになる、の 2 点を避けるため。

**レビューの要否はこのスキルが判断する**（レビューは高単価なため、全 PR 自動実行ではなく必要な PR に絞る）。
`git diff "$BASE_BRANCH"...HEAD` に以下のいずれかが含まれるなら「要」と判定し、ステップ 11 の冒頭で
`/security-review` をコメント投稿する（下記「コメント投稿」のイディオムを使う）:

- 認証認可・セッション・トークン・パスワード・暗号・シークレットの取り扱いに触れる変更
- テナント / User Pool 境界（`app_id` / `pool_id` / `owner_tenant_id` スコープ、RLS）に関わる変更
- 決済・Webhook 受信・外部システム連携の変更
- 入力を解釈する処理（SQL / 外部コマンド / パス操作 / デシリアライズ / リダイレクト / CORS / Cookie）の変更
- 新規 API エンドポイントの追加、権限チェックの変更
- `.github/workflows/**` / Terraform / 依存関係（lock ファイル）の変更

明らかに該当しない場合（ドキュメント・UI 文言・スタイル・テストのみ等）は依頼しない。**迷ったら依頼する（安全側）**。
CI の指摘（該当行へのインラインコメントとして投稿される）への対応はステップ 11 のレビュー対応ループで行い、
対応後の再実行も `/security-review` コメントで依頼する。
レビューワークフローが未導入のリポジトリではコメントしても起動しないので、
その場合は `/dev:setup` での導入を案内する。

**ローカルで確認するプロジェクト規約 (バックエンド / テスト変更がある場合):**

プロジェクト固有の定番違反は CI のセキュリティレビューの対象外なので、ローカルでチェックする。規約の単一情報源は各ファイルに集約しているので、ここでは節を列挙せず、変更があれば該当ファイルの全節を開いて diff を読み直し、違反はコミット前に修正する (SKILL.md に節を複製しないことでドリフトを防ぐ):

```bash
# 規約はこのプラグインに同梱（プロジェクトの .claude/rules/ に同じ相対パスがあればそちらを優先）。
# 右辺の表記はスキル読み込み時に Claude Code がプラグインの実パスへ置換する（`:-` などの修飾を付けると置換されない）。
# 置換されなかった場合だけキャッシュを探す。旧バージョンが残っていることがあるので最新版を選ぶ
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
if [ ! -d "${PLUGIN_ROOT:-/nonexistent}/rules" ]; then
  PLUGIN_ROOT=$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache" -mindepth 4 -maxdepth 4 \
    -type d -path '*/dev/*' -name rules 2>/dev/null | sort -V | tail -1)
  PLUGIN_ROOT="${PLUGIN_ROOT%/rules}"
fi
# 解決に失敗したら黙って進まない（$PLUGIN_ROOT が空だと / 直下を指し、以降の Read が全て外れる）
[ -d "${PLUGIN_ROOT:-/nonexistent}/rules" ] && echo "PLUGIN_ROOT=$PLUGIN_ROOT" || echo "PLUGIN_ROOT_NOT_FOUND"
```

- `backend/src/**/*.py` の変更 → `$PLUGIN_ROOT/rules/backend.md`（および配下の domain / application ルール）
- `backend/test/**/*.py` の変更 → `$PLUGIN_ROOT/rules/backend/test/test.md`

### 2. PR の存在確認

ステップ 1-a で取得済みの `PR_NUMBER` で分岐する（再取得は不要）。

- **`PR_NUMBER` が空（PR 未作成）** → ステップ 3（新規作成フロー）へ
- **`PR_NUMBER` に値がある** → ステップ 7（更新フロー、PR 説明欄の更新から開始）へ

---

## 新規作成フロー

### 3. PR テンプレートの取得と適用

PR テンプレートの正本は **org 共通リポジトリ `<owner>/.github` の `.github/PULL_REQUEST_TEMPLATE.md`**（`<owner>` は対象リポジトリの owner。org 名はハードコードせず実行時に導出する）。GitHub の default community health files の仕様どおり、**対象リポジトリに自前のテンプレートがあればそちらが優先**され、無い場合に org 共通テンプレートが適用される。org 共通テンプレートはワーキングツリーに存在しないため、`Read` ではなく以下で取得する:

```bash
# ローカル (リポジトリ固有) のテンプレートが最優先。無ければ org 共通テンプレートを取得する。
TEMPLATE=$(ls .github/PULL_REQUEST_TEMPLATE.md PULL_REQUEST_TEMPLATE.md \
             docs/PULL_REQUEST_TEMPLATE.md 2>/dev/null | head -1)
if [ -n "$TEMPLATE" ]; then
  cat "$TEMPLATE"
else
  OWNER=$(gh api 'repos/{owner}/{repo}' --jq .owner.login)
  gh api -H "Accept: application/vnd.github.raw" \
    "repos/${OWNER}/.github/contents/.github/PULL_REQUEST_TEMPLATE.md"
fi
```

取得したテンプレートに従って PR を作成する。**各セクションの埋め方（Todo Issue からのマッピング・🙆‍♂️ やったこと の書き方など）はテンプレートの HTML コメントに集約しているので、それを順守する**（SKILL.md に複製しない）。取得に失敗した場合 (ネットワーク断・`gh` 未認証など) のみ「💡 概要 / 🙆‍♂️ やったこと / 🙅‍♂️ やらないこと / ✔️ 動作確認」の構成で書く。

対応する Todo Issue (org 共通リポジトリ `<owner>/.github` の `.github/ISSUE_TEMPLATE/todo.md` 構造) があれば、コメントのマッピングに従って各セクションをそのまま転記する。無い PR (バグ修正・ドキュメントのみ等) は直接埋める。

### 4. チェックリスト

PR 作成前に以下を確認:
- [ ] lint / 型チェックがパスする（Taskfile があるリポジトリなら `task style:check`）
- [ ] テストがパスする（Taskfile があるリポジトリなら `task dev:test`）
- [ ] ベースブランチ (`$BASE_BRANCH`) の最新をマージ済み
- [ ] コミットメッセージが適切
- [ ] レビュアーを指定

### 5. PR の作成方式を確認

- **レビュー依頼できる状態** → 通常の PR として作成
- **まだ作業中** → Draft PR として作成（`--draft` フラグを付与）

### 6. PR 作成

PR 本文はステップ 3 で取得した PR テンプレートに従い、`/tmp/pr_body.md` に書き出しておく。

**`gh pr create` を使わないこと。** gh の生成系サブコマンドは GraphQL mutation を使い、claude.ai/code のセッションでは 403 でブロックされる（同系統の `gh issue create` で実測確認済み）。REST で作成する。
本文は改行やバッククォートを含むため `-f` ではなく **`jq -n --rawfile` で JSON を組み立てて `--input`** で渡す:

```bash
# BASE_BRANCH / BRANCH はステップ 1-a の値をリテラルで埋める
jq -n --arg title "PR タイトル" --arg head "$BRANCH" --arg base "$BASE_BRANCH" \
      --rawfile body /tmp/pr_body.md --argjson draft false \
  '{title:$title, head:$head, base:$base, body:$body, draft:$draft}' > /tmp/pr_create.json

PR_NUMBER=$(gh api --method POST "repos/{owner}/{repo}/pulls" --input /tmp/pr_create.json --jq .number)

# Assignees にユーザー自身を指定する (gh pr create --assignee @me の代替)
ME=$(gh api user --jq .login)
jq -n --arg me "$ME" '{assignees:[$me]}' > /tmp/pr_assignees.json
gh api --method POST "repos/{owner}/{repo}/issues/${PR_NUMBER}/assignees" --input /tmp/pr_assignees.json > /dev/null

echo "PR_NUMBER=$PR_NUMBER"
```

- `base` はステップ 1-a で確定した値を必ず明示する（別ベース運用に備える）
- Draft で作る場合（ステップ 5 で選んだとき）は `--argjson draft true` にする

作成後、ステップ 10（Diff コメントの投稿）へ進む。新規作成時は削除対象の既存コメントがないため、ステップ 9 はスキップする。

---

## 更新フロー

### 7. PR 説明欄の更新

> ⚠️ **CRITICAL: PR 本文の全体置換は破壊的操作。** PR 本文はユーザがブラウザから手動編集する前提 (「✔️ 動作確認」のスクショ・`| Before | After |` 表・デプロイリンク等)。これらの追記を消さないこと。

#### 7-a. 現在の本文を取得して上書きリスクを検出

最新のコミット履歴と差分を反映する前に、必ず現在の本文を取得し、ユーザの追記がないか確認する:

```bash
gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}" --jq .body > /tmp/pr_current_body.md
```

取得した本文をステップ 3 の PR テンプレートと比較し、テンプレートのプレースホルダ (`<!-- ... -->`) 以外に **実質的な追記がないか** を判定する。具体的には以下のいずれかが見つかれば「ユーザ追記あり」と判定:

- 「✔️ 動作確認」セクションにスクリーンショット URL、`<details>` ブロック、デプロイ実行リンク (`actions/runs/...`)、Before/After 比較表の画像、計測結果などが入っている
- 「💡 概要」「🙆‍♂️ やったこと」「🙅‍♂️ やらないこと」のいずれかに、コミットメッセージや diff から導出できない説明（背景・意図・制約など）が記載されている
- テンプレートに無いセクションが追加されている

「ユーザ追記あり」と判定した場合は、`AskUserQuestion` で「ユーザの追記を保持したまま◯◯セクションのみ更新してよいか」を確認する。**回答を得るまで `PATCH .../pulls/${PR_NUMBER}` は実行しない**。

#### 7-b. 安全な部分更新

ユーザ追記を保持する場合、`/tmp/pr_current_body.md` を `Read` ツールで読み込み、`Edit` ツールで対象セクション（通常は「🙆‍♂️ やったこと」「🙅‍♂️ やらないこと」）のみを書き換える。書き換えた内容を以下で反映する:

```bash
jq -n --rawfile body /tmp/pr_current_body.md '{body:$body}' > /tmp/pr_body_patch.json
gh api --method PATCH "repos/{owner}/{repo}/pulls/${PR_NUMBER}" --input /tmp/pr_body_patch.json > /dev/null
```

ユーザ追記がない（テンプレートのプレースホルダのままで実質的な追加情報がない）と確認できた場合のみ、以下の方式で全体置換してよい:

```bash
cat > /tmp/pr_current_body.md <<'EOF'
更新後の PR 本文
EOF
jq -n --rawfile body /tmp/pr_current_body.md '{body:$body}' > /tmp/pr_body_patch.json
gh api --method PATCH "repos/{owner}/{repo}/pulls/${PR_NUMBER}" --input /tmp/pr_body_patch.json > /dev/null
```

- ステップ 3 の PR テンプレートのセクション構造は維持する
- 新しいコミットで追加・変更された内容を「やったこと」セクションに反映する

> ⚠️ 万一ユーザ追記を上書きしてしまった場合は、末尾の「## トラブルシューティング: 上書きしてしまった本文の復元」を参照。

### 8. Draft PR の状態確認

PR 説明欄の更新後、Draft かどうかを確認する:

```bash
gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}" --jq .draft
```

- **Draft でない場合** → ステップ 9（既存 Diff コメントの削除）へ
- **Draft の場合** → レビュー依頼できる状態なら Ready for Review の PR に変換し、それ以外は Draft PR のままにしてください
  - **Draft のまま更新** → ステップ 9 へ
  - **Ready for Review に変更** → ステップ 8-a（動作確認チェック）へ

#### 8-a. 動作確認チェック（Draft → Ready 変更時）

Ready for Review に変更する前に、更新済みの PR 説明欄の「✔️ 動作確認」セクションの内容を確認する。

PR 本文の「✔️ 動作確認」セクション（`### ✔️ 動作確認` から次の `###` セクションまで）を取得し、以下の判定を行う:

**変更を許可する条件（いずれかを満たせば OK）:**
1. 動作確認の結果が記載されている（スクリーンショット、録画、Before/After 表に画像、テスト結果など、テンプレートのプレースホルダ以外の実質的な内容がある）
2. 動作確認が不要である旨が記載されている（例：「動作確認不要」「動作確認は不要です」「確認不要」「N/A」など）

**変更をブロックする条件:**
- 上記いずれの条件も満たさない場合（セクションがテンプレートのままで何も記載されていない場合）

ブロック時はユーザーに以下を伝える:
> Draft PR を Ready for Review に変更するには、「✔️ 動作確認」セクションに動作確認の結果を記載するか、動作確認が不要である旨を記載してください。

ユーザーが「動作確認は不要」と回答した場合は、**ステップ 7-b と同じ手順** で「✔️ 動作確認」セクションに「動作確認不要」と部分更新してから Ready for Review に変更する（本文全体置換は禁止）。

#### 8-b. Ready for Review への変更

動作確認チェックを通過したら、Draft を解除する:

Draft の解除は REST に無い。claude.ai/code では GraphQL mutation の `gh pr ready` が 403 になるため CCR 専用ルートを使い、
CCR ルートが存在しない（404）ローカル CLI では `gh pr ready` にフォールバックする（いずれも実測確認済み）:

```bash
gh api --method POST "repos/{owner}/{repo}/pulls/${PR_NUMBER}/ccr/ready_for_review" > /dev/null 2>&1 \
  || gh pr ready "$PR_NUMBER"
```

> Draft に戻す場合も同じ形で、`POST repos/{owner}/{repo}/pulls/${PR_NUMBER}/ccr/convert_to_draft`
> → 失敗したら `gh pr ready --undo "$PR_NUMBER"`。

---

### 9. 既存 Diff コメントの削除

更新前の古い Diff コメントを削除してから新しいコメントを投稿する。
既存のレビューコメントを取得し、自分が投稿したコメントを削除する:

```bash
# PR_NUMBER はステップ 1-a の値をリテラルで埋める
CURRENT_USER=$(gh api user --jq .login)

# 自分が投稿した Diff コメントの ID を取得して削除
gh api repos/{owner}/{repo}/pulls/${PR_NUMBER}/comments \
  --jq ".[] | select(.user.login == \"${CURRENT_USER}\") | .id" \
  | while read -r comment_id; do
    gh api repos/{owner}/{repo}/pulls/comments/${comment_id} --method DELETE
  done
```

---

## Diff コメントの記載

### 10. Diff コメントの投稿

PR 作成・更新後、レビュアーが実装意図を理解できるように、変更差分の重要な箇所にコメントを追加する。

- `gh api` を使って PR の Diff にレビューコメントをまとめて投稿する
- 以下のような箇所にコメントを付ける:
  - 設計判断やトレードオフがある箇所
  - 既存コードの変更理由
  - 注意が必要なロジック
  - レビュアーが「なぜこうしたのか？」と疑問に思いそうな箇所
- コメントは日本語で記載する
- 自明な変更（import の追加、フォーマット変更など）にはコメント不要
- `side` は追加・変更行なら `RIGHT`、削除行なら `LEFT` を指定する
- **プレフィックス (`[must]` / `[imo]` / `[ask]` / `[nits]`) は付けない** — 作成者の Diff コメントはレビュー指摘ではなく実装意図の補足説明なので、説明文として淡々と書く。

#### コメント投稿方法

レビューAPIを使い、全コメントを1回のリクエストでまとめて投稿する。
`gh api` の `-f "comments[0][path]=..."` 形式は GitHub API が配列として認識しないため、JSON ファイル経由の `--input` を使用すること:

```bash
# PR_NUMBER はステップ 1-a の値をリテラルで埋める
COMMIT_ID=$(gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}" --jq .head.sha)

cat > /tmp/pr_review.json <<EOF
{
  "event": "COMMENT",
  "commit_id": "${COMMIT_ID}",
  "comments": [
    {
      "path": "対象ファイルパス",
      "line": 42,
      "side": "RIGHT",
      "body": "コメント内容"
    },
    {
      "path": "別のファイルパス",
      "line": 10,
      "side": "RIGHT",
      "body": "別のコメント"
    }
  ]
}
EOF

gh api repos/{owner}/{repo}/pulls/${PR_NUMBER}/reviews \
  --method POST \
  --input /tmp/pr_review.json
```

---

## CI 監視とレビュー対応

### 11. CI 監視とレビューコメントへの対応・返信

PR 作成 / 更新後は、まずステップ 1-c の判断に従い、必要な場合のみ PR に `/security-review` とコメントしてセキュリティレビューを依頼する。続いて CI を監視し、失敗はフックをスキップせず修正・再 push。CI 通過後は bot / 人のレビュー（本文・インライン・会話）を全件確認し、`[must]`/`[imo]`/`[ask]`/`[nits]` 規約と CLAUDE.md の指摘対応方針で採否を判断。修正は CI 再監視、全件に日本語で返信する。修正 push 後の再レビューは、コードレビューなら `/code-review`、セキュリティレビュー由来の指摘なら `/security-review` を PR にコメントして依頼する（いずれもコメント完全一致でのみ起動する）。

## コメント投稿のイディオム

**`gh pr comment` を使わないこと**（同上）。PR へのコメントは
issue comments の REST エンドポイントに投稿する。本文は `jq -n` で JSON にしてから渡す:

```bash
jq -n --arg body "/security-review" '{body:$body}' > /tmp/pr_comment.json
gh api --method POST "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments" --input /tmp/pr_comment.json > /dev/null
```

レビュー依頼コメント（`/code-review` / `/security-review`）は**完全一致でのみ起動する**ため、
前後に文字を足さないこと。

## 注意事項

- ベースブランチに直接コミットせず、feature ブランチから PR を出す。ベースはステップ 1-a で特定した `$BASE_BRANCH` を使い、`main` 決め打ちにしない
- PR タイトルはシンプルかつ 70 文字以内の非エンジニアでもやっていることが理解できる命名にする
- Assignees には必ずユーザー自身のアカウントを指定する（`--assignee @me`）
