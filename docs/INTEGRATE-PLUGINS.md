# fastship-plugins を devops に統合し、PUBLIC にする

> 2026-10-09 合意済み。fastship-plugins は削除する。README のタイトルは変えない。

## 目的
- 組織共通の開発基盤（CI / Taskfile / lefthook / mise / Claude Code プラグイン）を 1 リポジトリで管理し、2 リポジトリ間の同期をなくす
- devops を PUBLIC にし、Claude Code on the web・CI・各開発者の環境から認証なしで読めるようにする

## 背景
| 問題 | 内容 |
|:--|:--|
| 2 リポジトリの食い違い | `dev:setup` スキルが旧名 `github-workflows` を参照したまま。`ruleset:github-workflows` スキルと devops のワークフローが同じ規約を別々に持つ |
| 相互参照 | devops の Claude ワークフロー 3 本が fastship-plugins の `dev` プラグインを読み込み、`dev` プラグインは devops を案内する |
| devops が PRIVATE | Task の remote include / lefthook の remotes で devops を取るのに、環境ごとの認証が要る（Git Credential Manager のダイアログ、CI のトークン） |
| Web で devops を読めない | Web セッションの GitHub proxy は、セッションに追加したリポジトリしか通さない。追加すると複数リポジトリのセッションになり、リポジトリの `.claude/settings.json` の hooks が読まれなくなる |

## 調査結果
### Claude Code on the web（2026-10-09 に app.fastship.jp のセッションで確認）
| 確認 | 結果 |
|:--|:--|
| セッションに追加していない PUBLIC リポジトリ（fastship-plugins）の `git clone` / `git ls-remote` | ✅ 通る |
| セッションに追加していないリポジトリへの `api.github.com` | ❌ 403（`GitHub access to this repository is not enabled for this session`） |
| `github.com/.../releases/download/...` からの直接ダウンロード | ✅ 通る |
| `mise.run` | ❌ 既定のネットワーク設定（Trusted）では許可されていない |

mise は mise.lock の `url`（直接ダウンロード）を使うため、`api.github.com` を遮断してもツールは入る（手元で再現して確認）。Web で一部ツールが 403 になった原因は未確定で、統合後に再確認する。

### 公開前チェック
| 項目 | 結果 |
|:--|:--|
| シークレット（全履歴 70 コミット、gitleaks） | ✅ 検出なし |
| ワークフロー・Taskfile・SETUP.md | ✅ シークレットは名前の参照のみ |
| スクリーンショット（docs/0/） | ✅ org 名と設定画面のみ |
| 過去の PR・Issue・Actions のログ | ⚠️ 公開される。公開前に目を通す |
| `self-claude.yml` | ⚠️ 誰でも書ける Issue / コメントで起動する。`claude.yml` は `CONTRIBUTOR` も許可するが、claude-code-action が書き込み権限を API で確認するため、外部の人は Claude を動かせない |

## 方針
### 1. fastship-plugins を devops に取り込む
履歴を残すため、`git subtree add` ではなく、fastship-plugins の履歴をそのままマージする（`git merge --allow-unrelated-histories`）。

```
devops/
  .claude-plugin/marketplace.json   # fastship-plugins から移す（name: fastship のまま）
  plugins/dev/                      # 〃
  plugins/ruleset/                  # 〃
  .github/                          # 既存
  Taskfile.yml / lefthook.yml / mise.toml / mise.lock
  CONTRIBUTING.md                   # fastship-plugins のものを統合
```

- マーケットプレイス名は `fastship` のままにする。`dev@fastship` などのプラグイン名は変わらない
- 利用者はマーケットプレイスの URL だけ追加し直す（`/plugin marketplace add https://github.com/theindiehacker/devops.git`）
- devops の Claude ワークフロー 3 本の `plugin_marketplaces` を devops に変える
- `plugin.json` の `repository` を devops に変える
- `dev:setup` の旧名 `github-workflows` を devops に直す
- fastship-plugins は、切り替えを確認したあとに削除する

### 2. devops を PUBLIC にする
公開前に次を行う。

1. 過去の PR・Issue・Actions のログに、公開して困る内容がないか確認する
2. Actions の設定で、fork からの PR のワークフロー実行に承認を必須にする（PUBLIC にしてから設定できる）
3. PUBLIC にする

### 3. バージョンの付け方
| 対象 | バージョン | 利用者の参照 |
|:--|:--|:--|
| reusable workflow / Taskfile / lefthook | リポジトリの git タグ（Release ワークフロー） | `@vX.Y.Z` / `ref: vX.Y.Z` |
| プラグイン | `plugins/<name>/.claude-plugin/plugin.json` の `version` | マーケットプレイスは main を取得 |

プラグインだけの変更ではタグを切らない。タグを切ると、全リポジトリに Renovate の参照更新 PR が届くため。

## 実施手順
1. ✅ この設計の合意
2. ✅ devops に fastship-plugins の履歴をマージし、参照先を直す PR を出す
3. 公開前チェックの残り（PR・Issue・Actions のログの確認）
4. devops を PUBLIC にし、fork PR の承認設定を入れる
5. 2 の PR をマージする。Claude ワークフローのプラグインの取得先が devops になるため、PUBLIC にする前にマージすると、他リポジトリの CI がプラグインを取れなくなる
6. 利用者がマーケットプレイスを devops で追加し直す
7. Web セッションで、devops をセッションに追加せずに `task --yes init` と commit が通るか確認する
8. fastship-plugins を削除する

## 対象外
- Web 用のセットアップ（Setup script / SessionStart hook）は、統合後に別の設計で扱う
