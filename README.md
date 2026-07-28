# claude-plugins

theindiehacker プロジェクト群で使う Claude Code プラグインのマーケットプレイスです。
fastship.jp で運用してきた `.claude/` 資産 (スキル・エージェント・フック・規約) を、全社のどのリポジトリからも使えるようにプラグイン化しています。

## 使い方

### 個人でインストールする

```
/plugin marketplace add theindiehacker/claude-plugins
/plugin install <plugin-name>@theindiehacker
```

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
    "fastship@theindiehacker": true
  }
}
```

## プラグイン一覧

| プラグイン | 説明 |
| --- | --- |
| [fastship](plugins/fastship/) | 全社共通の開発ワークフロー。DDD スキル (`/fastship:issue` → `/fastship:refine` → `/fastship:design` → `/fastship:dev` → `/fastship:push-pr`、`/fastship:conform`)・エージェント (`tdd` / `domain-model-reviewer`)・DDD 規約ハンドブック (`rules/`)・規約自動注入/ガードフック |

## リポジトリ構成

```
claude-plugins/
├── .claude-plugin/
│   └── marketplace.json   # マーケットプレイスカタログ
└── plugins/
    └── fastship/          # 全社共通の開発ワークフロープラグイン
```
