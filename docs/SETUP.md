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
> 本リポジトリのリリースタグ(`v*`)の tag ruleset は「5.」で設定する。

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
| Bypass list | Renovate 用 GitHub App(`renovate-<org 名>`)を `For pull requests only` で追加(下記参照)<br/>開発者が 1 人だけの場合は「1.」の注意書きを参照 |
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

※ 承認が Required approvals にカウントされるのは write アクセス保持者のレビューのみ。PR 作成者本人による自己承認はできない。<br/>
※ Renovate の更新 PR を承認なしで自動マージするため、Renovate 用 GitHub App を Bypass list に追加する。必須ワークフローのルールセット(2.3・2.4・2.7)には追加しないこと(失敗した検査を無視してマージされるようになる)

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
> Claude ワークフロー(`.github/workflows/claude*.yml`)も呼び出し側の全リポジトリで write 権限付きのプロンプトとして動くため、同じ File patterns(`.github/workflows/**`)で本ルールの対象になる

| 設定項目 | 値                        |
|:-------:|:-------------------------|
| Ruleset Name | `🛠️ 検知ワークフロー変更の承認必須化`    |
| Enforcement status | `Active`                 |
| Bypass list | Renovate 用 GitHub App(`renovate-<org 名>`)を `For pull requests only` で追加(「✅ PR の承認を必須化」を参照)<br/>承認者が 1 人だけの場合は「1.」の注意書きを参照 |
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
| `github-workflows` | `main` | `.github/workflows/python.yml` | Python の規約(uv での依存管理)・lint・書式・セキュリティ(ruff の `S` ルール)・型・依存関係 |
| `github-workflows` | `main` | `.github/workflows/typescript.yml` | TypeScript の規約(Bun での依存管理)・lint・書式・型・未使用パッケージ |

> 必須ワークフローは対象 repo のコードを実行しない解析に揃える。`python.yml` と `typescript.yml` の検査だけが例外で、`uv sync` / `bun install` による依存導入と、その環境上で動く mypy(プラグインを含む) / lint-imports / deptry / Biome / knip / tsc が対象 repo のコードに触れる。
> 検査の対象や厳しさ、src レイアウトの自パッケージの解決は、対象 repo の設定ファイル(`mypy.ini` / `[tool.deptry]` / `[build-system]` / `biome.json` / `knip.json` / `tsconfig.json` など)に従う。

**導入時の前提** : 次に当てはまる repo は、対応するまで必須チェックが fail する。

1. `[tool.mypy]` に `files` / `packages` / `modules` を宣言していない(mypy は検査対象が決まらないと usage エラーで終わる)
2. `autogenerated by uv` で始まらない `requirements*.txt` を依存管理に使っている(`pyproject.toml` の隣にあるもの、`pyproject.toml` が無い repo では Python コードがある場合のみ対象)
3. `bun.lock` をコミットしていない(`bun install --frozen-lockfile` が失敗する)
4. `@biomejs/biome` / `knip` / `typescript` を devDependencies に持たない(`package.json` がある repo のみ対象)
5. ruff の `S` ルール(bandit 相当。`S101` を除く)に違反している(repo の `ignore` では外せない。誤検知は `# noqa: Sxxx` か `per-file-ignores` で個別に外す)

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
※ `astral-sh/ruff-action` / `astral-sh/setup-uv` は `python.yml` が使用する。

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
## 4. 🧠 Claude ワークフロー

### 4.1 組織シークレットを登録する

🔗 Organization → Settings → Secrets and variables → Actions → **New organization secret**

以下の**どちらか一方**を登録し、Repository access は `Private repositories` にする。public リポジトリにはリポジトリシークレットとしても登録しない(fork PR の差分経由でトークンを読み出される恐れがあるため)。

| Name | 値 |
|:-----|:--|
| `CLAUDE_CODE_OAUTH_TOKEN` | `claude setup-token` で発行した OAuth トークン(Pro / Max プラン) |
| `ANTHROPIC_API_KEY` | Anthropic API キー |

### 4.2 Claude GitHub App をインストールする

https://github.com/apps/claude を Organization にインストールし、Repository access を `All repositories` にする。

### 4.3 各リポジトリに呼び出し側のワークフローを追加する

1. 最新のリリースタグ(例: `v1.0.0`)のコミット SHA を確認する(`^{}` の行があればそちらを使う)

```shell
git ls-remote https://github.com/theindiehacker/github-workflows 'refs/tags/v1.0.0^{}' 'refs/tags/v1.0.0'
```

2. [`.github/workflows/self-claude.yml`](../.github/workflows/self-claude.yml) を `.github/workflows/claude.yml` としてコピーし、各 job の `uses:` を 1. の値で書き換える

```diff
-    uses: ./.github/workflows/claude-code-review.yml
+    uses: theindiehacker/github-workflows/.github/workflows/claude-code-review.yml@<SHA>  # v1.0.0
```

3. main にマージ後、PR に `/code-review` とコメントしてレビューが投稿されることを確認する

---
## 5. 🏷️ リリースタグ

呼び出し側が reusable workflow(「4.」「6.」)を `@<SHA>  # vX.Y.Z` で参照し、Renovate で更新できるようにするため、本リポジトリには semver のリリースタグを付ける。

**リリースの手順** : 🔗 本リポジトリ → Actions → **🏷️ Release** → **Run workflow**

1. Branch は `main` のまま、`bump` で上げるバージョン(下表)を選んで実行する
2. main の先頭のコミットに、次のバージョンのタグ `vX.Y.Z` と GitHub Release(リリースノートは前回のタグ以降の PR から自動生成)が作られる
3. 呼び出し側の Renovate が新しいタグを検出し、参照の更新 PR を作る

| bump | 対象 |
|:----|:----|
| `major` | 呼び出し側の変更が必要なもの(`on:`・job の `permissions`・`secrets`・`inputs` の追加や変更、トリガーのコメントの変更など) |
| `minor` | 呼び出し側の変更が不要な機能追加・挙動の変更(モデルの変更など) |
| `patch` | 不具合の修正、action・ツールの更新 |

- 前回のリリース以降に入った変更のうち、いちばん大きい区分を選ぶ。呼び出し側の挙動が変わらない変更(ドキュメントなど)だけならリリースしない
- タグがまだ無い場合は、`bump` に関係なく `v1.0.0` になる
- main の先頭にすでにタグが付いている場合は、何も作らずに失敗で終わる(新しい変更をマージしてから実行し直す)
- `main` 以外のブランチを選んだ場合は job が skip される
- タグは `GITHUB_TOKEN` で作るため、タグの作成は制限していない。write 権限を持つメンバーは、ワークフローの書き換えや直接の push でレビューを経ないコミットにもタグを付けられる(呼び出し側ではマイナー・パッチの更新が自動マージされる)。write 権限は信頼できるメンバーだけに付与する
- 実行は 1 回ずつ行う。実行中に続けて 2 回以上実行すると、待機中の実行は最後の 1 回に置き換えられる

<details><summary><b>タグを変えられないようにする(tag ruleset)</b></summary>

付けたタグが別のコミットに付け替えられると、`# vX.Y.Z` のコメントと実際の SHA がずれ、Renovate の更新も壊れるため、タグの更新・削除を禁止する。

🔗 Organization → Settings → Repository → Rulesets → **New ruleset** → **New tag ruleset**

**「🔒 リリースタグの変更禁止」**

| 設定項目 | 値 |
|:-------:|:--|
| Ruleset Name | `🔒 リリースタグの変更禁止` |
| Enforcement status | `Active` |
| Bypass list | 空のまま |
| Target repositories | `Select repositories` → `github-workflows` のみ |
| Target tags | `Include by pattern` → `v*` |

Rules セクションで以下にチェック:

- ✅ Restrict updates
- ✅ Restrict deletions
- ✅ Block force pushes

※ 誤ったタグを付けた場合も付け替えず、修正を入れた次のバージョンを出す。

</details>

<details><summary><b>Immutable releases を有効にする</b></summary>

🔗 本リポジトリ → Settings → General → Releases

- ✅ **Enable release immutability**

公開済みの GitHub Release のタグとアセットを変更・削除できなくなる(有効化より前に作った Release には適用されない)。tag ruleset と合わせて、リリースタグが指すコミットを固定する。
最初のリリース(`v1.0.0`)の前に有効にしておく。

</details>

---
## 6. 🏗️ Terraform ワークフロー

`terraform init` が要る検査(validate / test)を、各リポジトリから reusable workflow [`terraform.yml`](../.github/workflows/terraform.yml) として呼び出す。
fmt / tflint / trivy は必須ワークフロー(2.)で実行済みのため、ここでは行わない。

| 検査 | 内容 |
|:----|:----|
| validate | 対象ディレクトリごとに `terraform init -backend=false` → `terraform validate`。結果は PR に annotation で表示する |
| lock ファイル | `.terraform.lock.hcl` があるディレクトリでは `init -lockfile=readonly` を使い、`required_providers` と合わない場合や、linux_amd64 のハッシュが無い場合に失敗させる |
| test | ディレクトリ直下か `tests/` に `*.tftest.hcl` があれば `terraform test` を実行する |

- 対象ディレクトリは、変更の有無に関係なく repo 全体(`*.tf` / `*.tf.json` を含むディレクトリ。`.terraform` 配下を除く)。Terraform のファイルが無いリポジトリでは何もせず success で終わる
- CI は linux_amd64 で動く。lock ファイルには `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` のように、開発に使うプラットフォームに加えて linux_amd64 のハッシュも記録しておく
- クラウドの認証情報・secrets は渡さない。`terraform test` は `command = plan` と `mock_provider` で完結するテストだけを書く(実際のクラウドに `apply` するテストは失敗する)
- Terraform は HashiCorp の `SHA256SUMS` を GPG 署名で検証してから導入する。provider は `actions/cache` でキャッシュする

### 6.1 各リポジトリに呼び出し側のワークフローを追加する

1. 「4.3」の 1. と同じ手順で、最新のリリースタグのコミット SHA を確認する
2. `.github/workflows/terraform.yml` を以下の内容で追加し、`uses:` の `<SHA>` と `# vX.Y.Z` を 1. の値で書き換える

```yaml
name: "🏗️ terraform"

on:
  pull_request:

permissions: {}

# 同一 PR に連投された run のみ束ねて追い越しキャンセル
concurrency:
  group: terraform-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  terraform:
    permissions:
      contents: read
    uses: theindiehacker/github-workflows/.github/workflows/terraform.yml@<SHA>  # vX.Y.Z
    with:
      terraform-version: "1.16.0"
      # 省略時は *.tf / *.tf.json を含む全ディレクトリ。限定する場合は repo ルートからの相対パスを改行区切りで書く
      # working-directories: |
      #   modules/vpc
      #   examples/vpc
```

| inputs | 必須 | 内容 |
|:------|:----|:----|
| `terraform-version` | ✅ | 使う Terraform の版(例: `1.16.0`)。`1.9.0` 以上(init の診断を annotation にするため `init -json` を使う) |
| `working-directories` | | 検査するディレクトリ(改行区切り)。省略時は自動検出 |

- トリガーは `pull_request` にする。`pull_request_target` から呼び出すと失敗する(PR のコードを base の権限で実行させないため)
- `permissions` は `contents: read` だけを渡す。`secrets` は渡さない
- `concurrency` は呼び出し側で設定する(呼び出し先で設定すると、1 つの run から複数回呼んだときに互いにキャンセルされるため)
- `terraform test` が使う provider・module は PR に書かれたものが実行されるため、権限を増やさないこと

3. main にマージ後、PR で **Terraform を検査** の job が成功することを確認する
