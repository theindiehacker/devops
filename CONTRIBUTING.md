# Contributing

`theindiehacker/claude-plugins` は組織全体に配布する Claude Code プラグインのマーケットプレイスです。このドキュメントではプラグインの開発方法を説明します。

## 構成

```
.claude-plugin/marketplace.json      # マーケットプレイス定義（配布するプラグイン一覧）
plugins/<plugin-name>/
  .claude-plugin/plugin.json         # プラグインのマニフェスト（name / version / description など）
  skills/<skill-name>/SKILL.md       # スキル定義（/<plugin-name>:<skill-name> で起動）
  rules/                             # プロジェクト規約（各 SKILL.md から参照）
```

新しいプラグインを追加する場合は `plugins/` 配下にディレクトリを作成し、`.claude-plugin/marketplace.json` の `plugins` 配列にエントリを追加してください。

## スキルの追加・変更

- `plugins/<plugin-name>/skills/<skill-name>/SKILL.md` を作成・編集する
- frontmatter の `name` はディレクトリ名と一致させる
- `description` には起動条件とユースケースを具体的に書く（トリガー精度に直結する）
- 既存スキルからの参照（他の SKILL.md 内のスラッシュコマンド表記など）が残っていないか、リネーム時は必ず `grep` で確認する

## ⚠️ バージョン管理（重要）

**プラグインの中身を変更したら、必ず対応する `plugins/<plugin-name>/.claude-plugin/plugin.json` の `version` を上げてください。**

`/plugin marketplace update` はマーケットプレイスの `main` ブランチを取得しますが、インストール済みプラグインのローカルキャッシュ（`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`）は `version` が変わらない限り更新されません。`version` を上げ忘れると、リポジトリ側の変更（スキル追加・リネーム・内容修正など）がユーザー環境に一切反映されず、「新しいスキルが表示されない」といった不具合の原因になります。

バージョンの上げ方の目安（[SemVer](https://semver.org/lang/ja/) 準拠）:

| 変更内容 | 例 | バンプ |
|---|---|---|
| 誤字修正・軽微な文言調整 | 説明文のタイポ修正 | patch (`0.2.0` → `0.2.1`) |
| スキル・ルールの追加、既存スキルの機能拡張 | 新しい SKILL.md の追加 | minor (`0.2.0` → `0.3.0`) |
| 既存スキル名の変更・削除など互換性のない変更 | `/dev:foo` → `/dev:bar` へのリネーム | minor 以上（利用者への周知も合わせて行う） |

## PR 作成・マージ

PR の作成・更新・CI 監視・レビュー対応は `dev:push-pr` スキル（`/dev:push-pr`）に従ってください。主な流れ:

1. `main` から `<種別>/<内容>` 形式のブランチを作成する（例: `feat/`, `fix/`, `docs/`, `chore/`, `refactor/`）
2. 変更をコミットし、PR テンプレートに従って PR を作成する
3. CI（`.github/workflows/` のスキャン各種）が通過することを確認する
4. 必要に応じてレビューを受け、マージする

## 動作確認

変更をローカルで確認する場合は、対象リポジトリで以下を実行してキャッシュを更新してください（`version` を上げていることが前提です）。

```
/plugin marketplace update theindiehacker
```
