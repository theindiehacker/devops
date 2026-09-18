---
description: E2E テスト (Playwright) の実装・実行ルール
summary: E2E は本物の API / DB / Mailpit を叩く。テストデータはユニークなメールで分離し、非同期経路は expect.poll / toPass で待つ
paths:
  - "frontend/e2e/**"
  - "frontend/playwright.config.ts"
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
- メール検証は #411 の Tokens VO 修正で**逐次**の二重サブミット / リトライは同じトークンに収束するようになった。ただし「有効トークンが 0 の状態への**真に並行な**再要求」では両者が別トークンを発行し片方が last-writer-wins で消える窓が残る (backend `User.request_email_verification` の docstring 参照。根治は FOR UPDATE / 種別ごと部分 unique が候補で backend の follow-up)。この窓が閉じるまで、ヘルパー `registerAndVerify` は届いた検証メールのトークンを newest-first で順に踏んで有効な 1 つを採用する自己修復を維持する (CI 実測で 8 register→9 token / verify 401 の残存フレークを確認済み)
- #439 (password-reset の flaky 401) の根因は**メール plain text パートの行折り返しによるトークン切断**だった: html2text の既定 (78 桁折り返し) は「ハイフン直後が英字」のときだけ折り返すため、ランダムな UUID の字種次第でトークン途中に改行が入り、正規表現が途中で切れた無効リンクを拾って consume が 401 になり続ける (二重発行・TTL・ポーリング不足のいずれでもない)。根治は backend の `to_plain_text` (bodywidth=0) と mailpit ヘルパーの改行復元 (`unwrapLines`) の 2 層。メール本文からリンクを抽出する新ヘルパーは必ず `unwrapLines` 経由にする。切り分け用に backend `DriverManagerUser.find_by_token` がミス時に「行は存在するが join 不可視」を WARN で出す (WARN なしのミス = 行自体が無い)

## 実行

- `task dev:e2e` (compose 起動込み。`task dev:e2e -- e2e/authority/signup.spec.ts` で spec 指定)
- `bunx playwright` は Node で動く。`bunx --bun` は使わない
- CI: `.github/workflows/e2e-test.yml` がローカルと同じ `task dev:e2e` を実行する

## backend テストとの住み分け

- API 単体の仕様 (バリデーション / 権限 / エラー) は `backend/test/acceptance` (pytest) で検証する
- E2E は「画面 → API → DB → メール → 画面」を横断するユーザーフローのみに絞り、ケース数を増やしすぎない
