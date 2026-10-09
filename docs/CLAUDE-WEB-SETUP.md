# Claude Code on the web のセットアップ

> 2026-10-09 合意済み（SessionStart hook で、スクリプトは devops から取得する）。

## 目的
Claude Code on the web（以下 Web）のセッションでも、ローカルと同じように pre-commit（`task security:check`）を動かす。

## 背景
2026-10-09 に app.fastship.jp の Web セッションで確認したところ、task も pre-commit フックも入っていなかった。そのため、gitleaks が動かないままコミットされ、stop hook に促されて push まで進んだ。

## 調査結果
### Web の環境（公式ドキュメントと実機での確認）
| 項目 | 事実 |
|:--|:--|
| 既定のネットワーク（Trusted） | github.com、GitHub Releases、raw.githubusercontent.com は通る。mise.run、mise.jdx.dev は通らない |
| api.github.com | セッションに追加していないリポジトリへの API は 403（実機で確認） |
| PUBLIC リポジトリ | セッションに追加しなくても clone できる（実機で確認） |
| プラグイン | リポジトリの `enabledPlugins` を書いても、Web にはプラグインが入らない |
| Setup script | 環境設定画面に書く。root で実行され、結果は約 7 日キャッシュされる。**0 以外で終わるとセッションが始まらない** |
| SessionStart hook | リポジトリの `.claude/settings.json` に書く。開始と再開のたびに動く。失敗してもセッションは続く。`CLAUDE_ENV_FILE` に export を書けば、後続の Bash に PATH を渡せる。**複数リポジトリのセッションでは読まれない** |
| Web かどうかの判定 | `CLAUDE_CODE_REMOTE=true` |

### mise のツールの取得
mise.lock には、プラットフォームごとの直接ダウンロードの URL（`url`）が入っている。api.github.com と mise.jdx.dev を遮断しても、9 ツールすべてを mise.lock から入れられた（手元で再現）。

## 方針
### SessionStart hook で入れる
| 方式 | 長所 | 短所 |
|:--|:--|:--|
| **A. SessionStart hook（推奨）** | リポジトリにコミットするので、バージョン管理でき、`/dev:setup` で配れる。失敗してもセッションは止まらない | セッションのたびにインストールする（20 秒前後）。複数リポジトリのセッションでは動かない |
| B. Setup script | キャッシュが効くので速い。複数リポジトリのセッションでも動く | 環境ごとに画面で設定する。バージョン管理できない。失敗するとセッションが始まらない |

A を採用する。B は、速さが問題になったときに足す。

### 各リポジトリに置くもの
```json
// .claude/settings.json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "curl -fsSL https://raw.githubusercontent.com/theindiehacker/devops/vX.Y.Z/scripts/claude-web-setup.sh | bash"
          }
        ]
      }
    ]
  }
}
```

- スクリプトは devops に置き、Taskfile / lefthook と同じタグで参照する（コピーしない）
- `.claude/settings.json` は各リポジトリにコピーする（`/dev:setup` で配る）。参照するタグは Renovate で更新する

### devops に置くスクリプト（`scripts/claude-web-setup.sh`）
1. `CLAUDE_CODE_REMOTE` が `true` でなければ何もしない（ローカルでは動かさない）
2. mise を GitHub Releases から入れる。バージョンと SHA-256 はスクリプトに固定し、Renovate（`renovate.json` の `scripts/*.sh` 用の custom manager）で更新する
3. `$CLAUDE_PROJECT_DIR` で `mise trust` と `mise install --yes` を実行する。ツールは mise.lock から入り、`postinstall` で `lefthook install` まで済む
4. mise と各ツールの PATH を `CLAUDE_ENV_FILE` に書く（Claude が実行する `git commit` から lefthook と task を呼べるように）
5. 失敗しても 0 で終わり、警告だけ出す。CI の必須ワークフロー（gitleaks）が最後の砦になる

## 確認結果
Docker（Ubuntu 24.04、amd64）で Web の環境を再現し、app.fastship.jp の main で確認した。api.github.com、mise.run、mise.jdx.dev は hosts で塞いだ。

| 確認 | 結果 |
|:--|:--|
| 初回のセットアップ | ✅ mise と 9 ツールが入り、pre-commit フックが登録される（39 秒。amd64 のエミュレーション込み） |
| 2 回目（セッションの再開） | ✅ 8 秒。`CLAUDE_ENV_FILE` に同じ行を重ねて書かない |
| `git commit` | ✅ gitleaks が動く。devops のファイルはインデックスに混ざらない |
| シークレット（Slack 形式のダミー）を含めた commit | ✅ `leaks found: 1` で止まる |

## 実機での確認方法
1. app.fastship.jp に `.claude/settings.json` を足す（参照先はこのスクリプトを含むリリースタグ）
2. その状態で Web セッションを開き、次を確かめる
   - セッション開始時に、ツールとフックが入る
   - `git commit` で gitleaks が動く
   - Slack 形式のダミーのシークレットで、コミットが止まる
   - remote include（devops の Taskfile）が取れる

## 対象外
- 複数リポジトリのセッション（SessionStart hook が読まれない）。必要になったら Setup script を足す
- Taskfile の `init` が mise.run を使う件（ローカル用なので変えない）
