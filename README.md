# fastship-plugins
組織全体に配布する Claude Code プラグインのマーケットプレイス

## How To
## 🧰 Install
⚠️ 事前に `gh auth login` で認証を完了していること
```
/plugin marketplace add https://github.com/theindiehacker/fastship-plugins.git
```

<details><summary><b>🛠️ 開発(<code>/dev:</code>)プラグイン</b></summary>

```
/plugin install security-guidance@claude-plugins-official
/plugin install dev@fastship
```

</details>

## 🔄 Update
マーケットプレイスを最新化してから、インストール済みプラグインを更新する。

```
/plugin marketplace update fastship
```

以降、`/plugin` コマンドからプラグイン一覧・更新状況を確認できる。
