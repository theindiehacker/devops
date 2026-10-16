---
name: e2e
description: E2E テスト (Playwright) の実装・実行ルール。E2E は本物の API / DB / Mailpit を叩く。テストデータはユニークなメールで分離し、非同期経路は expect.poll / toPass で待つ
paths:
  - "frontend/e2e/**"
  - "frontend/playwright.config.ts"
user-invocable: false
---

# E2E テストルール (Playwright)

## 配置と命名

- E2E テストは `frontend/e2e/{コンテキスト名}/*.spec.ts` に置く (コンテキスト名は backend モジュールに合わせる: authority / tenant / billing / chat ...)
- テスト名は日本語で「ユーザーが何をできるか」を書く (backend pytest と同じ流儀)
- 共通処理は `frontend/e2e/helpers/` に置く

## 方針

- 本物の API / DB / Mailpit を叩く。ネットワークモック (`page.route` 等) は使わない
- テストデータはユニークなメールアドレス (`e2e-{timestamp}-{random}@example.com`) で分離する。DB の TRUNCATE / 事後クリーンアップはしない (並列・再実行に安全)
- 非同期経路 (検証メール配送 / テナント作成 = Pub/Sub) は `expect.poll` / `expect(...).toPass` で待つ。`waitForTimeout` の固定 sleep は禁止
- セレクタは `getByRole` / `getByLabel` / `getByText` を優先し、`data-testid` はテキストを持たない要素 (例: アバターボタン) に限る
  - `getByRole("alert")` は Next.js の `__next-route-announcer__` (role=alert) にも一致するため、エラー文言は `getByText` で絞る
- 並行した再要求で検証トークン等が複数発行されうる経路では、届いたメールのトークンを新しい順に試して有効な 1 つを採用するヘルパーにする (最初の 1 通に決め打ちしない)。有効なトークンが無い状態への真に並行な再要求では、別々のトークンが発行されて片方が後勝ちで消えることがあり、決め打ちすると 401 のフレークになる
- メール plain text パートからリンク／トークンを抜くときは、行の折り返しを復元してから正規表現にかける。html2text 等の既定の折り返し (78 桁) はトークンの途中に改行を入れることがあり、途中で切れた無効なリンクを拾って 401 になり続けるフレークの原因になる。メールからリンクを抜くヘルパーは必ず折り返しの復元を通す (送信側も plain text を折り返さない設定にしておく)

## 実行

- `task dev:e2e` (compose 起動込み。`task dev:e2e -- e2e/authority/signup.spec.ts` で spec 指定)
- `bunx playwright` は Node で動く。`bunx --bun` は使わない
- CI: `.github/workflows/e2e-test.yml` がローカルと同じ `task dev:e2e` を実行する

## backend テストとの住み分け

- API 単体の仕様 (バリデーション / 権限 / エラー) は `backend/test/acceptance` (pytest) で検証する
- E2E は「画面 → API → DB → メール → 画面」を横断するユーザーフローのみに絞り、ケース数を増やしすぎない
