---
name: conform
description: 変更 diff を規約（プラグイン同梱 rules/ + プロジェクトの .claude/rules/）に照らして違反を洗い出し提示する（--fix で修正まで適用）。/simplify がプロジェクト非依存の品質を見るのに対し、conform は会社標準の DDD 規約準拠に特化する。
argument-hint: "[--fix] [diff範囲]"
model: opus
---

# 規約準拠チェック (conform)

変更した diff を **規約のうち「その変更ファイルにマッチするルール」だけ**を規範に照合し、違反を洗い出す。規約の供給源は 2 つ: **このプラグイン同梱の `rules/`（会社標準）** と **プロジェクトの `.claude/rules/`（リポジトリ固有。同名はこちらが優先）**。既定は**提示のみ**で、`--fix` を付けたときだけ修正まで適用する（DDD の意味論修正は大きく書き換わるため、安全側に倒した確定方針）。

## 手順

### 1. 対象 diff の確定 → 変更ファイル取得 → マッチするルール列挙

**必ず 1 回の `Bash` 呼び出しで実行する。** Bash ツールはシェル変数を呼び出し間で保持しないため、
分割すると `FILES` / `RANGE` / `--fix` が失われ、「マッチ 0 件」と区別のつかない空結果になる。

```bash
# $ARGUMENTS は起動時の入力に展開される。--fix フラグと diff 範囲（--fix 以外の語）を分離する。
FIX=false; RANGE=""
for a in $ARGUMENTS; do
  [ "$a" = "--fix" ] && FIX=true || RANGE="$a"
done

# プラグインの導入先を特定する。右辺の表記はスキル読み込み時に Claude Code がプラグインの実パスへ置換する
# （`:-` などの修飾を付けると置換されない）。置換されなかった場合だけキャッシュを探す。
# 旧バージョンが残っていることがあるので最新版を選ぶ
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
if [ ! -d "${PLUGIN_ROOT:-/nonexistent}/rules" ]; then
  PLUGIN_ROOT=$(find "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache" -mindepth 4 -maxdepth 4 \
    -type d -path '*/indiehacker/*' -name rules 2>/dev/null | sort -V | tail -1)
  PLUGIN_ROOT="${PLUGIN_ROOT%/rules}"
fi
if [ ! -d "${PLUGIN_ROOT:-/nonexistent}/rules" ]; then
  echo "PLUGIN_ROOT_NOT_FOUND"
elif ! FILES=$(bash "$PLUGIN_ROOT/skills/conform/scripts/changed_files.sh" "$RANGE"); then
  # 変更ファイル取得の失敗（不正な diff 範囲・git リポジトリ外など）を「変更なし」と混同しない
  echo "CHANGED_FILES_FAILED"
elif [ -z "$FILES" ]; then
  echo "NO_CHANGED_FILES"
else
  echo "FIX=$FIX RANGE=${RANGE:-<未コミット変更>}"
  # マッチ判定は手で推測せず、同梱の突合スクリプトに委ねる。
  # xargs は ARG_MAX で分割起動しうるので、最後に sort -u で重複を潰す。
  echo "$FILES" | tr '\n' '\0' \
    | xargs -0 python3 "$PLUGIN_ROOT/skills/conform/scripts/rules_matcher.py" | sort -u
fi
```

出力の見方（この 3 つは必ず区別して報告する。どれも「違反なし」ではない）:

- `PLUGIN_ROOT_NOT_FOUND` → プラグインの導入先を特定できていない。**チェックを実行できなかった**旨を報告して停止する。
- `CHANGED_FILES_FAILED` → diff 範囲の指定ミスや git リポジトリ外。原因を報告して停止する。
- `NO_CHANGED_FILES` → 変更ファイルが無い。「変更なし」で終了する。

上記のいずれでもなければ、`ルールパス<TAB>要約` の行が並ぶ（プロジェクトルールは相対パス、プラグイン同梱ルールは絶対パス。どちらもそのまま `Read` できる）。行が 0 件なら「準拠チェック対象のルール無し」で終了する。`FIX=true` なら以降のステップで修正まで適用する。

### 2. マッチしたルール全文を Read

ステップ 1 で挙がったルールファイルを**全て `Read`** する。これが照合の正。フックの要約ではなく**全文**で照らす（conform は精査が仕事）。

### 3. 違反の洗い出し（3 経路を統合）

diff の各ファイルを対応ルールに照らし、違反を集める:

- **(a) 意味論（DDD）**: `backend/src/**/domain/**` または `**/application/**` に変更があれば、`Agent` ツールで `subagent_type: "indiehacker:domain-model-reviewer"` を呼ぶ。対象 diff・**ステップ 1 で得た DDD 規約の絶対パス（`rules/backend/src/domain/model/*.md` と `application.md`）を prompt に列挙**・（あれば）Issue 番号／設計書を渡し、貧血ドメイン・集約境界越え Tx・primitive obsession・ロジック漏れ・用語ドリフト・境界キー欠落を鑑定させる。**パスを渡さないと、サブエージェントは規約を見つけられず要約だけで鑑定してしまう**（プラグインはプロジェクト外にあり `Glob` で見つからないため）。サブエージェントなのでルール全文はそちらで消費され、メイン会話は findings だけ受け取る。
- **(b) 機械チェック**: `task style:check`（ruff / mypy / deptry / import-linter）を走らせ、構造違反・型・未使用依存を拾う（Taskfile に定義がないリポジトリではスキップ）。CI でも走るが、ここで確認して取りこぼしを防ぐ。
- **(c) ルール個別照合**: (a)(b) が拾わない規約は、ステップ 2 で読んだルール全文と diff を突き合わせて Claude 自身が照合する（例: `test.md` の「定数を使わずハードコード／テストクラス内プライベート・継承基底の禁止」、`application.md` の「メソッド 50 行以内」、`migration.md` の「テーブル追加時は core.py の tables に登録」、`dpo.md` の「生成には集約のみ」）。

各違反に次を必ず含める:

- `file:line`
- どのルールのどの項目に反するか（ルールファイルパス + 該当箇所）
- なぜ問題か（どの不変条件／境界が壊れるか、具体的な失敗シナリオ）
- 具体的な直し方（どの集約のどのメソッドに引き上げる等）

### 4. 提示（既定の終着点）

違反をレビュープレフィックス規約の重大度順に整理して提示する:

- `[must]`: 規約に明確に反する（必ず修正すべき）
- `[imo]`: より良い準拠の提案（採否は判断）
- `[ask]`: 設計意図の確認

`--fix` が無ければここで終了し、「修正するなら `/indiehacker:conform --fix` を再実行、または手動修正」と案内する。

### 5. `--fix` 指定時の修正適用

`--fix` があるときだけ実行する:

1. `[must]` を中心に修正を適用する（`Edit`）。意味論の大規模リファクタ（集約へのロジック引き上げ・VO 化・イベント化）は domain-model-reviewer の直し方に従う。
2. 修正対象パスにマッチするルールは**書き始める前に Read** する（フックが要約を注入するが、修正では全文根拠が要る）。
3. 修正後 `task style:fix` → `task style:check` → `task dev:test` を通す（Taskfile に定義がある場合。フックを `--no-verify` で迂回しない）。
4. テストが追随できない大規模変更は**適用を止めて提示に留め**、`AskUserQuestion` で「別アプローチ / 人間に引き継ぐ / このまま強行」を確認する。
5. 修正結果（変更ファイル + 通したチェック）を報告する。

## 注意事項

- **既定は提示のみ**。`--fix` を付けたときだけ書き換える（意味論修正は大きく書き換わるため、承認済みの安全方針）。
- **diff スコープに閉じる**。変更していないファイルの既存違反は掘り起こさない（見つけてもメモ提示に留め、勝手に直さない）。
- **突合は同梱の `scripts/rules_matcher.py` が正**。どのルールが該当するかを手で推測しない（プラグインの rules-guard フックも同じルール群を正に読むが、実装は各自で持つ）。
- **意味論を二重判断しない**。DDD スメルは domain-model-reviewer に委譲し、conform は統合と非 DDD ルール（test / migration / infra）の照合に集中する。
- **過剰指摘を避ける**。表示用の一次データを無理に VO 化させる等の原理主義に陥らない。事故る／壊れる根拠のある違反だけ `[must]` にする。
