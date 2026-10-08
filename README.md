# 🛠️ Dev Ops
Organization 共通の CI / ruleset / Lefthook / Taskfile を管理するリポジトリ

```mermaid
graph TD;
    subgraph GitHub ["github.com"]
        devops("🛠️ devops")
        other1("📺 GitHub リポジトリ")
        other2("📺 GitHub リポジトリ")
        
        other1 & other2 -.->|<code>.github/workflows</code><br/>lefthook.yml / Taskfile.yml| devops
    end
    
    subgraph claude ["claude.ai/code"]
        other1 -->|git clone ...| clone1("📺 GitHub リポジトリ")
        
        agent(("🧠")) -->|<code>task *</code><br/><code>lefthook</code> 起動| clone1
    end
```

```yaml
# lefthook.yml
remotes:
  - git_url: https://github.com/theindiehacker/devops
    ref: v1.0.0
    configs:
      - lefthook.yml
```

```yaml
# Taskfile.yml
includes:
  common:
    taskfile: https://github.com/theindiehacker/devops.git//Taskfile.yml?ref=v1.0.0
    # 共通 lefthook.yml が `task security:check` を名前空間なしで呼ぶため、タスクをトップレベルに展開する
    flatten: true
    vars:
      # 共通設定（pyproject.toml / biome.json / .tflint.hcl）を取得する版。上の ref と同じタグにする
      DEVOPS_REF: v1.0.0
```

```yaml
# 各リポジトリの mise.toml
include = ["git::https://github.com/theindiehacker/devops.git//mise.toml?ref=v1.0.0"]
```

## ❓ 使い方
### 🎊 セットアップ

[docs/SETUP.md](./docs/SETUP.md) を参照して、実行してください。

### ✅ チェック

セキュリティチェック・リント・フォーマッターは `Taskfile.yml` に一元化しており、ローカルでも必須ワークフローでも同じタスクを実行します。
`task style:check` / `task style:fix` / `task security:check` で実行できます。詳細は [docs/CHECKS.md](./docs/CHECKS.md) を参照してください。
