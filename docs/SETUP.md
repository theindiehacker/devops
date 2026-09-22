# 🎊 セットアップ

> ⚠️ **前提** : GitHub Team プランを契約していること

## 0. 🏢 Organization の基本設定

<details><summary>🫆 <b>二要素認証を必須にする</b></summary>

🔗 Organization → Settings → Authentication security

![](./0/二要素認証を必須にする.png)
*チェックを入れてください*

⚠️ 二要素認証未設定のメンバーは org のリソースへアクセスできなくなり、outside collaborator は org から削除されるため、事前に周知すること
```text
【要対応・期限 ◯月◯日】GitHub の二要素認証(2FA)を設定お願いします。

◯月◯日より、GitHub にて二要素認証を必須化します。
期限までに設定がない場合、Organization のリポジトリなどのリソースにアクセスできなくなります。
(設定すればすぐにアクセスが回復します)

■ 設定手順(5 分程度)
1. https://github.com/settings/security を開く
2. "Two-factor authentication" の [Enable two-factor authentication] をクリック
3. 認証方法として「パスキー / セキュリティキー」「認証アプリ」「GitHub Mobile」のいずれかを選ぶ  ※ SMS は推奨しません

■ 設定済みか確認するには
https://github.com/settings/security を開き、"Two-factor authentication" が
有効(緑のチェック)になっていれば対応済みです。
```

</details>

<details><summary>💪 <b>組織のリポジトリに対するベース権限を設定する</b></summary>

🔗 Organization → Settings → Member privileges

 - 将来メンバーが増える前提で「職務分掌」を意識したい → `No permission`
 - 「組織メンバー＝基本的に全部のコードは見えてよい」という文化 & まだ少人数 → `Read`

![Base permissions](./0/Base%20permissions.png)

</details>

<details><summary>❌ <b>管理者しかリポジトリを作成できないにする</b></summary>

🔗 Organization → Settings → Member privileges

![](./0/Repository%20creation.png)
*意図しない公開リポジトリの作成を防ぐため、Private, Public 両方のチェックを外し、管理者しかリポジトリを作成できないようにする*

</details>

<details><summary>🚫 <b>組織のリポジトリを fork できないようにする</b></summary>

🔗 Organization → Settings → Member privileges

![](./0/Repository%20forking.png)
*チェックを外してください*

</details>

---
## 1. 👥 セキュリティチームを作成
Gitleaks や Trivy などがセキュリティ検知をした時に対応するチームを作成します。<br/>
PR でセキュリティ検知された際はこのチームからの Approve がないとマージできない運用にします。

1. Organization → **Teams** → **New team** でチーム「**security**」を作成
2. 対応者をメンバーに追加
3. Organization → Settings → **Organization roles** → **Role assignments** → **New role assignment** で、作成したチームに以下の 2 ロールをアサイン:

| ロール | 目的 |
|:------|:----|
| `Security manager` | 全リポジトリの Read 権限が自動付与され、2.5・2.6 の Required reviewers が**リポジトリごとのチーム登録(Add teams)なしで自動レビュアー指定**されるようになる(新規リポジトリも自動で対象)。org 全体のセキュリティアラートの閲覧・管理権限も付く |
| `All-repository write` | 承認が Required approvals にカウントされるのは write アクセス保持者のレビューのみのため、Read 相当の Security manager と併用する |

※ 自動レビュアー指定が機能するのは「リポジトリへの直接登録(Add teams)」か「Security manager ロール」の場合のみ。`All-repository write` など一般の org role だけでは、承認は可能になるがレビュアーの自動指定はされない。

> ⚠️ 承認者本人が作成した PR は自己承認できない。チームメンバーが 1 人だけの場合は、
> ルールセットの **Bypass list** に org 管理者を追加してマージする。

---
## 2. 📚 Organization ルールセットを設定
Organization ページ → Settings → Repository → Rulesets を選択し、以下のルールを設定して下さい。

> ⚠️ **前提** : branch ruleset(2.1〜2.7)が保護するのは default branch のみ。リリースも default branch(main)のマージ済みコミットから行う運用を前提とする。
> タグやリリースブランチを起点にデプロイする運用を導入する場合は、レビューを経ないコミットからタグを切れてしまうため、別途 tag ruleset / 対象ブランチの追加が必要。

### `New branch ruleset`

<details><summary><b>「🚫 main への直接 push 禁止」</b></summary>

| 設定項目 | 値                      |
|:-------:|:-----------------------|
| Ruleset Name | `🚫 main への直接 push 禁止` |
| Enforcement status | `Active`               |
| Target repositories | `All repositories` |
| Target branches | `Include default branch` |

Rules セクションで以下にチェック:

- ✅ Restrict deletions (デフォルトブランチの削除を制限する)
- ✅ Require a pull request before merging (マージ前にプルリクエストを必須とする)
- ✅ Block force pushes (リモートブランチへの強制プッシュを禁止)

</details>

<details><summary><b>「✅ PR の承認を必須化」</b></summary>

> 全 PR に人間のレビュー承認(1 名以上)がないとマージできないようにするルール

| 設定項目 | 値                        |
|:-------:|:-------------------------|
| Ruleset Name | `✅ PR の承認を必須化`         |
| Enforcement status | `Active`                 |
| Bypass list | 空のまま<br/>開発者が 1 人だけの場合は「1.」の注意書きを参照 |
| Target repositories | `All repositories`       |
| Target branches | `Include default branch` |

Rules セクションで以下のチェックを外す:

- ⬜︎ **Restrict deletions**
- ⬜︎ **Block force pushes**

以下のチェックを入れる:

- ✅ **Require a pull request before merging**

| 設定項目 | 値 |
|:--------|:--|
| Required approvals | `1` |
| Dismiss stale pull request approvals when new commits are pushed | ✅(承認後に push されたコミットが再レビューなしでマージされるのを防ぐ) |
| Require review from Code Owners | ❌ |
| Require approval of the most recent reviewable push | ❌ |
| Require conversation resolution before merging | ❌ |
| Allowed merge methods | `Merge` / `Squash` / `Rebase`(すべて許可) |

※ 承認が Required approvals にカウントされるのは write アクセス保持者のレビューのみ。PR 作成者本人による自己承認はできない。

</details>

<details><summary><b>「🔑 シークレットの混入検知」</b></summary>

| 設定項目 | 値                        |
|:-------:|:-------------------------|
| Ruleset Name | `🔑 シークレットの混入検知`         |
| Enforcement status | `Active`                 |
| Bypass list | 空のまま                     |
| Target repositories | `All repositories`       |
| Target branches | `Include default branch` |

Rules セクションで以下のチェックを外す:

- ⬜︎ Restrict deletions
- ⬜︎ Block force pushes

以下のチェックを入れる:

 - ✅ **Require workflows to pass before merging** (PRマージ前に指定したワークフローの成功を必須にする) — 「Add workflow」から以下を追加:

| Repository | Branch | Workflow |
|:-----------|:-------|:---------|
| `github-workflows` | `main` | `.github/workflows/gitleaks.yml` |

 - ✅ **Do not require workflows on creation**

</details>

<details><summary><b>「🛡️ 脆弱性・IaC 設定ミス検知」</b></summary>

| 設定項目 | 値 |
|:-------:|:--|
| Ruleset Name | `🛡️ 脆弱性・IaC 設定ミス検知` |
| Enforcement status | `Active` |
| Bypass list | 空のまま |
| Target repositories | `All repositories` |
| Target branches | `Include default branch` |

Rules セクションで以下のチェックを外す:

- ⬜︎ **Restrict deletions**
- ⬜︎ **Block force pushes**

以下のチェックを入れる:

- ✅ **Require workflows to pass before merging** (PRマージ前に指定したワークフローの成功を必須にする) — 「Add workflow」から以下を追加:

| Repository | Branch | Workflow |
|:-----------|:-------|:---------|
| `github-workflows` | `main` | `.github/workflows/trivy.yml` |
| `github-workflows` | `main` | `.github/workflows/zizmor.yml` |
| `github-workflows` | `main` | `.github/workflows/semgrep.yml` |
| `github-workflows` | `main` | `.github/workflows/ghalint.yml` |

- ✅ **Do not require workflows on creation**

</details>

<details><summary><b>「✔️ セキュリティ設定ファイル変更の承認必須化」</b></summary>

> セキュリティ検知の設定ファイル(`.gitleaksignore` / `.trivyignore` など)を変更する PR にセキュリティチーム(`security`)の承認を必須化するルール

| 設定項目 | 値                        |
|:-------:|:-------------------------|
| Ruleset Name | `✔️ セキュリティ設定変更の承認必須化`    |
| Enforcement status | `Active`                 |
| Bypass list | 空のまま<br/>承認者が 1 人だけの場合は「1.」の注意書きを参照                |
| Target repositories | `All repositories`       |
| Target branches | `Include default branch` |

Rules セクションで以下のチェックを外す:

- ⬜︎ **Restrict deletions**
- ⬜︎ **Block force pushes**

以下のチェックを入れる:

- ✅ **Require a pull request before merging**

| 設定項目 | 値 |
|:--------|:--|
| Required approvals | `0`(承認必須化は下記の Required reviewers で行う) |
| Dismiss stale pull request approvals when new commits are pushed | ✅ |
| Require review from Code Owners | ❌ |
| Require approval of the most recent reviewable push | ❌ |
| Require conversation resolution before merging | ❌ |
| Allowed merge methods | `Merge` / `Squash` / `Rebase`(すべて許可) |

同ルール内の **Require review from specific teams** に以下を追加:

| 設定項目 | 値                                                                                                                                                                                                        |
|:--------|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Reviewer | `security` チーム(「1.」で作成)                                                                                                                                                                                  |
| Approvals | `1`                                                                                                                                                                                                      |

File patterns:
```
.gitleaksignore
.gitleaks.toml
.trivyignore
.trivyignore.yaml
trivy.yaml
.github/trivy-image.yml
.github/trivy-image.yaml
.github/zizmor.yml
.semgrepignore
**/.semgrepignore
ghalint.yml
ghalint.yaml
.ghalint.yml
.ghalint.yaml
.github/ghalint.yml
.github/ghalint.yaml
```

※ `trivy.yaml`(リポジトリ直下)は Trivy が自動読込する設定ファイルで、`ignorefile` / `ignore-policy` により抑制先を差し替えられるため対象に含める。レビュー時はこの 2 項目が上記対象外のファイルを指していないかを確認する<br/>
※ `**/.semgrepignore` は Semgrepignore v2(Semgrep 1.117 以降のデフォルト)でサブディレクトリの `.semgrepignore` も有効になるため対象に含める<br/>
※ zizmor の設定はワークフロー側(`.github/workflows/zizmor.yml` の `--config` / `--no-config`)で `.github/zizmor.yml` に固定しているため、自動探索され得る他パス(リポジトリ直下の `zizmor.yml` 等)の列挙は不要

</details>

<details><summary><b>「🛠️ 検知ワークフロー変更の承認必須化」</b></summary>

> 必須ワークフローの実体(本リポジトリの `.github/workflows/`)を変更する PR にセキュリティチーム(`security`)の承認を必須化するルール。
> 必須ワークフロー(2.3〜2.4・2.7)は本リポジトリの `main` 上の定義を参照しているため、検知を弱める変更(severity の引き下げ・`exit-code: 0` 化など)が通常の承認(2.2)だけで通ると org 全体の検知が無効化されてしまう
> Claude レビューワークフロー(`.github/workflows/claude-*.yml`)も呼び出し側の全リポジトリで write 権限付きのプロンプトとして動くため、同じ File patterns(`.github/workflows/**`)で本ルールの対象になる

| 設定項目 | 値                        |
|:-------:|:-------------------------|
| Ruleset Name | `🛠️ 検知ワークフロー変更の承認必須化`    |
| Enforcement status | `Active`                 |
| Bypass list | 空のまま<br/>承認者が 1 人だけの場合は「1.」の注意書きを参照 |
| Target repositories | `Select repositories` → `github-workflows` のみ |
| Target branches | `Include default branch` |

Rules セクションで以下のチェックを外す:

- ⬜︎ **Restrict deletions**
- ⬜︎ **Block force pushes**

以下のチェックを入れる:

- ✅ **Require a pull request before merging**

| 設定項目 | 値 |
|:--------|:--|
| Required approvals | `0`(承認必須化は下記の Required reviewers で行う) |
| Dismiss stale pull request approvals when new commits are pushed | ✅ |
| Require review from Code Owners | ❌ |
| Require approval of the most recent reviewable push | ❌ |
| Require conversation resolution before merging | ❌ |
| Allowed merge methods | `Merge` / `Squash` / `Rebase`(すべて許可) |

同ルール内の **Require review from specific teams** に以下を追加:

| 設定項目 | 値 |
|:--------|:--|
| Reviewer | `security` チーム(「1.」で作成) |
| Approvals | `1` |

File patterns:
```
.github/workflows/**
```

</details>

<details><summary><b>「✏️ スタイルチェック」</b></summary>

> コードのスタイルチェックを必須化するルール。セキュリティ検知(2.3〜2.6)とは性質が異なるため別ルールセットで管理する

| 設定項目 | 値                        |
|:-------:|:-------------------------|
| Ruleset Name | `✏️ スタイルチェック`            |
| Enforcement status | `Active`                 |
| Bypass list | 空のまま(下記「例外運用」を参照)        |
| Target repositories | `All repositories`(同上)  |
| Target branches | `Include default branch` |

Rules セクションで以下のチェックを外す:

- ⬜︎ **Restrict deletions**
- ⬜︎ **Block force pushes**

以下のチェックを入れる:

- ✅ **Require workflows to pass before merging** (PRマージ前に指定したワークフローの成功を必須にする) — 「Add workflow」から以下を追加:

| Repository | Branch | Workflow | 検査内容 |
|:-----------|:-------|:---------|:--------|
| `github-workflows` | `main` | `.github/workflows/actionlint.yml` | ワークフロー定義の構文 |
| `github-workflows` | `main` | `.github/workflows/tflint.yml` | Terraform の lint |
| `github-workflows` | `main` | `.github/workflows/terraform-fmt.yml` | Terraform の書式 |
| `github-workflows` | `main` | `.github/workflows/shellcheck.yml` | シェルスクリプトの lint |
| `github-workflows` | `main` | `.github/workflows/python.yml` | Python の規約(uv での依存管理)・lint・書式・型・依存関係 |
| `github-workflows` | `main` | `.github/workflows/typescript.yml` | TypeScript の規約(Bun での依存管理)・lint・書式・型・未使用パッケージ |

> 必須ワークフローは対象 repo のコードを実行しない解析に揃える。`python.yml` と `typescript.yml` の検査だけが例外で、`uv sync` / `bun install` による依存導入と、その環境上で動く mypy(プラグインを含む) / lint-imports / deptry / Biome / knip / tsc が対象 repo のコードに触れる。
> 検査の対象や厳しさ、src レイアウトの自パッケージの解決は、対象 repo の設定ファイル(`mypy.ini` / `[tool.deptry]` / `[build-system]` / `biome.json` / `knip.json` / `tsconfig.json` など)に従う。

**導入時の前提** : 次に当てはまる repo は、対応するまで必須チェックが fail する。

1. `[tool.mypy]` に `files` / `packages` / `modules` を宣言していない(mypy は検査対象が決まらないと usage エラーで終わる)
2. `autogenerated by uv` で始まらない `requirements*.txt` を依存管理に使っている(`pyproject.toml` の隣にあるもの、`pyproject.toml` が無い repo では Python コードがある場合のみ対象)
3. `bun.lock` をコミットしていない(`bun install --frozen-lockfile` が失敗する)
4. `@biomejs/biome` / `knip` / `typescript` を devDependencies に持たない(`package.json` がある repo のみ対象)

**例外運用** : ランナーで依存を導入できない repo(private index の認証が必要など)が出た場合だけ、その repo を `Bypass list` に追加するか、`Target repositories` を `Dynamic list by property` 等に変更して対象から外す。規約・lint・書式の検査も併せて外れる。

- ✅ **Do not require workflows on creation**

</details>


### `New push ruleset`

<details><summary><b>「🚫 機密ファイルの push 禁止」</b></summary>

秘密鍵や `.env` などの機密ファイルを、履歴に入る前にサーバー側で拒否する push ルールセット
(Gitleaks は PR 時の検知のため、検知された時点で秘密情報はリモートの履歴に残っている)。
ファイル内容に対するコミット前のローカル検知は各リポジトリの git hook(任意運用)が担う。
2.1〜2.7 とは種類が異なり「**New push ruleset**」から作成する。

| 設定項目 | 値 |
|:-------:|:--|
| Ruleset Name | `🚫 機密ファイルの push 禁止` |
| Enforcement status | `Active` |
| Bypass list | 空のまま |
| Target repositories | `All repositories` |

Rules セクションで以下を設定:

✅ **Restrict file paths**

| File path |
|:----------|
| `.env` |
| `**/.env` |
| `id_rsa` |
| `**/id_rsa` |
| `id_ed25519` |
| `**/id_ed25519` |

※ `.env.example` 等のテンプレートを誤ブロックしないよう `.env.*` は対象にしない(実値が入った `.env.*` は Gitleaks が検知する)。

✅ **Restrict file extensions**

| Extension |
|:----------|
| `pem` / `key` / `p12` / `pfx` / `jks` / `keystore` / `tfstate` |

✅ **Restrict file size** — `5MB`

</details>

---
## 3. ⚙️ GitHub Actions のセキュリティ設定

Organization → Settings → **Actions** → **General** で以下を設定する。

<details><summary><b>Actions permissions(実行できる action の制限)</b></summary>

| 設定項目 | 値 |
|:--------|:--|
| Policies | `Allow <org>, and select non-<org> actions and reusable workflows` |
| Allow actions created by GitHub | ✅ |
| Allow specified actions and reusable workflows | 下記のパターンを登録 |

```
anthropics/claude-code-action@*,
aquasecurity/trivy-action@*,
astral-sh/ruff-action@*,
astral-sh/setup-uv@*,
docker/setup-buildx-action@*,
docker/build-push-action@*,
dorny/paths-filter@*,
oven-sh/setup-bun@*,
renovatebot/github-action@*
```

※ 各リポジトリが新しい外部 action を使う場合はこのリストへの追加が必要(SHA ピン留めは各ワークフロー側で行う)。<br/>
※ `oven-sh/setup-bun` は `anthropics/claude-code-action` が内部で使用する action のため併せて許可する(「4.」)。<br/>
※ `astral-sh/ruff-action` / `astral-sh/setup-uv` は `python.yml` が使用する。<br/>
※ `actions/create-github-app-token` は「Allow actions created by GitHub」で許可済みのため個別登録は不要。

</details>

<details><summary><b>Workflow permissions(<code>GITHUB_TOKEN</code> のデフォルト権限)</b></summary>

| 設定項目 | 値 |
|:--------|:--|
| Workflow permissions | `Read repository contents and packages permissions` |
| Allow GitHub Actions to create and approve pull requests | ❌(チェックを外す) |

- `permissions:` を明示しているワークフロー(本リポジトリのものを含む)には影響しない
- 「create and approve pull requests」を無効化することで、`GITHUB_TOKEN` による自己承認で 2.2 / 2.5 / 2.6 の承認必須化が迂回されるのを防ぐ

</details>

---
## 4. 🧠 Claude レビューワークフロー

PR のコメント(`/code-review` / `/security-review`)で Claude Code にレビューさせる reusable workflow を使うための設定。

<details><summary><b>組織シークレットを登録する</b></summary>

🔗 Organization → Settings → Secrets and variables → Actions → **New organization secret**

| Name | 値 |
|:-----|:--|
| `CLAUDE_CODE_OAUTH_TOKEN` | `claude setup-token` で発行した OAuth トークン(Pro / Max プラン) |
| `ANTHROPIC_API_KEY` | Anthropic API キー |

- **どちらか一方のみ**登録する
- Repository access は `Private repositories` にする。public リポジトリにもリポジトリシークレットとして登録しない
  - public リポジトリでは fork からの PR にもメンバーのコメントでレビューが走り、PR の差分に仕込まれた指示で Claude にトークンを読み出させる経路が残るため
  - シークレットを参照できないリポジトリではレビューは失敗し、進捗コメントに表示される

</details>

<details><summary><b>Claude GitHub App をインストールする</b></summary>

https://github.com/apps/claude を Organization にインストールし、Repository access を `All repositories` にする(新規リポジトリも自動で対象)。
action はこの App のトークンで進捗コメントやインラインコメントを投稿する。

</details>

<details><summary><b>前提となる他の設定</b></summary>

| 設定 | 参照 |
|:----|:----|
| `anthropics/claude-code-action` / `oven-sh/setup-bun` の実行許可 | 「3.」 Actions permissions |
| `claude-*.yml` の変更に security チームの承認を必須化 | 「2.」ルールセット「🛠️ 検知ワークフロー変更の承認必須化」(File patterns `.github/workflows/**` で自動的に対象) |

</details>
