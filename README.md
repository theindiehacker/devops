# claude-plugins

theindiehacker プロジェクト群で使う Claude Code プラグインのマーケットプレイスです。
fastship.jp で運用してきた `.claude/` 資産 (スキル・エージェント・フック・規約) を、全社のどのリポジトリからも使えるようにプラグイン化しています。

## 前提: private リポジトリの認証

このリポジトリは private です。Claude Code はマーケットプレイスの clone を **非対話** で実行するため、GitHub の認証情報がプロンプトなしで解決できる状態になっている必要があります。

事前に `gh auth login` などで、theindiehacker org にアクセスできるアカウントを認証しておいてください。設定できているかは次のコマンドで確認できます (ユーザー名やパスワードを聞かれなければ OK):

```
git ls-remote https://github.com/theindiehacker/claude-plugins.git
```

## 使い方

### 個人でインストールする

```
/plugin marketplace add https://<your-github-username>@github.com/theindiehacker/claude-plugins.git
/plugin install indiehacker@theindiehacker
```

`<your-github-username>` は theindiehacker org にアクセスできる GitHub アカウント名に置き換えてください。

> **なぜ URL にユーザー名を含めるのか**
> 短い形式 `/plugin marketplace add theindiehacker/claude-plugins` でも、GitHub アカウントを 1 つしか使っていないマシンなら動きます。
> ただしこの形式では認証情報をホスト単位 (`github.com`) でしか特定できないため、1 台のマシンで複数の GitHub アカウントを使い分けていると、どの認証情報を使うか決められず clone が失敗します。
> URL にユーザー名を含めておけばアカウントが一意に定まるので、どちらの環境でも確実に動きます。

### リポジトリ単位でチーム全員に配る (推奨)

各リポジトリの `.claude/settings.json` に以下を追記してコミットします。メンバーがそのリポジトリで Claude Code を起動すると、信頼確認のうえ自動でインストールされます:

```json
{
  "extraKnownMarketplaces": {
    "theindiehacker": {
      "source": {
        "source": "github",
        "repo": "theindiehacker/claude-plugins"
      }
    }
  },
  "enabledPlugins": {
    "indiehacker@theindiehacker": true
  }
}
```

この形式は URL にユーザー名を含められないため、各メンバーの手元で `github.com` の認証情報が一意に解決できる必要があります。複数アカウントを使い分けているメンバーは、代わりに「個人でインストールする」の手順を使ってください。

## プラグイン一覧

| プラグイン | 説明 |
| --- | --- |
| [indiehacker](plugins/indiehacker/) | 全社共通の開発ワークフロー。DDD スキル (`/indiehacker:issue` → `/indiehacker:refine` → `/indiehacker:design` → `/indiehacker:dev` → `/indiehacker:push-pr`、`/indiehacker:conform`)・エージェント (`tdd` / `domain-model-reviewer`)・DDD 規約ハンドブック (`rules/`)・規約自動注入/ガードフック |

## リポジトリ構成

```
claude-plugins/
├── .claude-plugin/
│   └── marketplace.json   # マーケットプレイスカタログ
└── plugins/
    └── indiehacker/       # 全社共通の開発ワークフロープラグイン
```
