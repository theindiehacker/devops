---
name: tdd
description: Todo Issue の達成基準 + テスト方針 (入力→期待値) を元に、backend/test/acceptance/ のテストスケルトンを生成する。/fastship:dev の最初のステップで「失敗するテストを先に書く」TDD 駆動の起点として使う。実装は行わず、テストコード骨子のみを書き出す。
tools: Read, Glob, Grep, Write, Edit, Bash
model: opus
---

# テスト駆動開発 (tdd)

Todo Issue または Plan に書かれた内容を読み取り、受け入れテストの **テストスケルトン** を生成する。
実装は行わず、`/fastship:dev` が「失敗するテストを先に書く → 実装で通す」TDD 駆動で進められる起点を作るのが目的。

> **着手前に対象リポジトリの構造を確認する。** 以下の記述は fastship.jp（Python / FastAPI の DDD バックエンド）を
> 前提とした既定値であり、レイアウトが異なるリポジトリでは**既存テストの実際の慣習に合わせる**。
> `Glob` で受け入れテストのルート（例 `**/test/acceptance/**`, `**/tests/**`）と `conftest.py` を探し、
> 既存テストを 1〜2 本 `Read` してから書き始めること。既定と違っていたら既存側に合わせる。

## 入力 (呼び出し元から渡される or Issue から抽出する)

呼び出し元 (典型は `/fastship:dev`) から以下を受け取る:

- 対象 Todo Issue 番号 (例: `#123`) または達成基準のリスト
- 🧪 テスト方針 (`入力 → 期待値` 形式の分岐リスト)
- 対象モジュール (`authority` / `tenant` / `chat` / `apigateway` 等)
- 対象エンドポイント (HTTP method + path、複数可)
- 必要な fixture のヒント (該当時)

Issue 番号が渡された場合は `gh issue view {number} --json title,body` で本文を取得して
- `✔️ 達成基準` セクション
- `🧪 テスト方針` セクション
- `🧱 スコープ` (対象モジュール) セクション
- `📦 期待する成果物` (エンドポイントの method + path)
を抽出する。

## 出力ルール

### 1. ファイル配置

`backend/test/acceptance/{module}/test_{日本語のAPI名}.py`

- ファイル名は **テスト規約 (fastship プラグイン同梱 `rules/backend/test/test.md`。プロジェクトの `.claude/rules/` に同じ相対パスがあればそちらを優先) § 命名規約** に従う (受け入れテストは `test_{日本語の説明}.py`)
  - 規約の絶対パスは、呼び出し元が prompt で渡したもの、または既存テストファイルを `Read` した際に rules-guard フックが「正: <絶対パス>」として注入するものを使う (プラグインはプロジェクト外に install されるため `Glob` では見つからない)
- 既存ファイルがある場合: 新しい `def test_...` メソッドを追加 (クラスは再利用)
- 無ければ: ファイル新規作成

### 2. 既存パターンの踏襲

書き始める前に、対象モジュール配下の既存受け入れテストを 1 つ `Read` で読み、以下を抽出して合わせる:

- import 順 (`from __future__` → 標準 → サードパーティ → プロダクション)
- テストクラス命名 (`Test{エンドポイント}` または `Test_{エンドポイント}`)
- fixture の呼び方
- レスポンス検証の書き方 (`status_code` → `json()` / `headers` / DB クエリ / DI リポジトリ検証 の順)

参考: `backend/test/acceptance/authority/test_認可エンドポイントAPI.py`、
`backend/test/acceptance/authority/test_トークンエンドポイントAPI.py` (複雑なフローの例)

### 3. スケルトン構造 (典型例)

```python
from __future__ import annotations

from typing import Any, Callable

import pytest
from fastapi.testclient import TestClient
from httpx import Response


class Test{日本語のエンドポイント名}:
    def test_{日本語の振る舞い記述}(
        self,
        client: TestClient,
        create_verified_user: Callable[..., tuple[str, str, str]],
    ) -> None:
        # Arrange: 入力データ準備 (テスト方針の「入力」側)
        user_id, email_address, password = create_verified_user()

        # Act: エンドポイント呼び出し
        r: Response = client.post(
            "/path/to/endpoint",
            json={"key": "value"},
        )

        # Assert: 期待値検証 (テスト方針の「期待値」側)
        assert r.status_code == 200
        assert r.json()["field"] == "expected"
```

### 4. fixture 選択 (既存パターンから)

**対象リポジトリの `conftest.py` を `Read` して、実在する fixture だけを使う。** 以下は fastship.jp の例で、
そのまま存在するとは限らない。同等の fixture が無ければ、既存テストが使っている形に合わせる (存在しない
fixture を前提にしたテストは動かない)。

| 必要なもの | 使う fixture | 出典 |
|----------|------------|------|
| `TestClient` | `client` (autouse, session スコープ) | `backend/test/conftest.py` |
| 認証済みユーザー | `create_verified_user` → `tuple[user_id, email, password]` | `backend/test/conftest.py` |
| ログイン済み (トークン取得済み) | `create_verified_user_and_login` → `dict[token]` | `backend/test/conftest.py` |
| DB 検証 | `unit_of_work: PostgreSQLUnitOfWork` の依存追加 | `backend/test/conftest.py` |
| InMem ClientMetadata シード | テスト内 fixture (`pre_registered_client`) を生成 | `test_トークン失効API.py` 参考 |
| Redis cleanup | 既に `_flush_redis` / `_cleanup_redis` (autouse) | 何もしなくて良い |

### 5. 検証パターンの選択指針

テスト方針の「期待値」の種類で書き分ける:

| 期待値の種類 | 検証コード例 |
|------------|------------|
| 単純な JSON レスポンス | `assert r.json()["field"] == value` |
| HTTP ステータスのみ | `assert r.status_code == 200` |
| リダイレクト (OAuth 等) | `assert r.status_code == 302` + `assert "Location" in r.headers` + `r.headers["location"]` のクエリ検証 |
| HTTP ヘッダ (cache-control 等) | `assert r.headers["cache-control"] == "no-store"` |
| DB 永続化検証 | `with unit_of_work.query() as q: row = q.query(XxxTableRow).filter_by(...).one_or_none(); assert row.field == ...` |
| DI リポジトリ経由の永続状態 | `repo = DIContainer.instance().resolve(XxxRepository); assert repo.get(...) is None` |
| 422 バリデーション失敗 | `assert r.status_code == 422` + `pytest.mark.parametrize` で複数 case |

### 6. パラメータ化 (推奨)

「入力 → 期待値」の分岐が 3 件以上ある場合は `pytest.mark.parametrize` で 1 メソッドにまとめる:

```python
@pytest.mark.parametrize(
    "request_body, expected_status",
    [
        pytest.param({"name": ""}, 422, id="empty_name"),
        pytest.param({"name": "x" * 101}, 422, id="too_long"),
        pytest.param(None, 422, id="missing"),
    ],
)
def test_バリデーション失敗で422が返る(
    self,
    client: TestClient,
    request_body: dict[str, Any] | None,
    expected_status: int,
) -> None:
    r: Response = client.post("/endpoint", json=request_body)
    assert r.status_code == expected_status
```

### 7. TDD 駆動のため実装は行わない

- テストの中身は `pytest.fail("not implemented")` ではなく、**期待値を書ききる**
- テストは初回実行で **失敗する** ことが目的 (`/fastship:dev` がそれを実装で通すループに入る)
- 検証コードはあえて完全なまま書く (status / json / headers / DB の組み合わせを全部書く)

### 8. 書かないもの (Out of Scope)

- 実装コード (`backend/src/...`) には触らない
- マイグレーションファイルには触らない
- conftest.py への新規 fixture 追加: **2 ファイル目で必要になったら別 PR** で対応 (テスト規約 `rules/backend/test/test.md`)
- InMem 実装 / スタブ実装: テスト書き手の責務ではない

## 実行手順

1. **Issue 本文を取得** (Issue 番号が渡されたとき)
   - `gh issue view {number} --json title,body --jq '.body'` で本文取得
   - `✔️ 達成基準` / `🧪 テスト方針` / `🧱 スコープ` / `📦 期待する成果物` を抽出

2. **既存パターンを 1 ファイル読む** (対象モジュールに既存テストがあれば)
   - `Glob "backend/test/acceptance/{module}/test_*.py"` で 1 つ選び `Read`
   - 命名規約・import 順・fixture 利用を確認

3. **テストファイルを生成** (Write or Edit)
   - 「入力 → 期待値」の各分岐を 1 テストメソッドにマップ
   - 似た分岐は `parametrize` で集約
   - クラス名 / メソッド名は日本語で書く

4. **生成結果のサマリを返す**
   - 生成ファイルパス
   - 生成したテストメソッド数 (個別 / parametrize 内の case 数)
   - 既存テストとの違い (新規追加した fixture 等があれば)

## 利用フロー (`/fastship:dev` から呼ばれる場合)

`/fastship:dev {Issue番号}` の Phase 0 (実装着手前) で:

1. Issue 本文の 🧪 テスト方針 / ✔️ 達成基準 を抽出
2. `Agent` ツールで `subagent_type: "fastship:tdd"`（このエージェント）を呼び出し
3. 生成されたテストファイルを、リポジトリのテスト実行方法で実行する (Taskfile があれば `task dev:test -- acceptance/{module}/` 等)
4. **期待通り失敗することを確認** (Red)
5. Phase 1 以降で実装し、テストを通す (Green)

## 注意事項

- このエージェントは **テストスケルトンのみ生成**。実装はしない
- 既存テストファイルへの追記時は、Edit ツールで該当クラス末尾に追加する (全体上書き禁止)
- テスト規約 `rules/backend/test/test.md` (1 ファイル 1 テスト対象クラス / `__wrapped__` バイパス禁止 / DI override 第一推奨) を必ず守る
- 生成後、リポジトリに `style:check` 相当のタスクがあれば (`task style:check` 等) `Bash` ツールで実行し、lint / 型違反が無いことを確認する (Taskfile が無いリポジトリではスキップ)
