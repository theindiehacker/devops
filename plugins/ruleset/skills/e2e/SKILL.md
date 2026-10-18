---
name: e2e
description: E2E テスト (Bun.WebView + bun test) の実装・実行ルール。E2E は本物の API / DB / Mailpit を叩く。テストデータはユニークなメールで分離し、非同期経路は条件を繰り返し確かめて待つ (固定の sleep は禁止)。スクリーンショットを残して Claude が画面を確かめる
paths:
  - "frontend/e2e/**"
user-invocable: false
---

# E2E テストルール (Bun.WebView + bun test)

ブラウザは [Bun.WebView](https://bun.com/docs/runtime/webview) (Mac は WebKit、それ以外は Chrome)、ランナーは `bun test`。Playwright と Node は使わない。

## 配置と命名

- E2E テストは `frontend/e2e/{コンテキスト名}/*.spec.ts` に置く (コンテキスト名は backend モジュールに合わせる: authority / tenant / billing / chat ...)
- テスト名は日本語で「ユーザーが何をできるか」を書く (backend pytest と同じ流儀)
- 共通処理は `frontend/e2e/helpers/` に置く。サーバーの起動は `frontend/e2e/setup.ts` (`bun test --preload`) が行う

## 書き方

- ページは `openPage(path)` (helpers/browser.ts) で開き、`await using` で受ける (テストを抜けるときに閉じる)
- `Bun.WebView` を直接 `new` しない。backend の選択・`--no-sandbox` (root で動く環境で要る)・`url: false` (開発者の普段の Chrome に繋がない) を helpers/browser.ts に集める
- 操作は `view.click(selector)` → `view.type(text)` / `view.press(key)`。`click(selector)` は押せるようになるまで待つ。座標クリック `click(x, y)` は使わない
- セレクタは CSS。`label` の `for`・`name`・`aria-label` など、画面の意味に沿った属性を優先し、`data-testid` はテキストを持たない要素 (例: アバターボタン) に限る
- 表示の確認は `waitForText` などのヘルパー (helpers/expect.ts) で、条件を繰り返し確かめて待つ。`Bun.sleep` で決め打ちの時間を待たない
  - `role="alert"` は Next.js の `__next-route-announcer__` にも付くため、エラー文言は文言そのもので確かめる
- `view.evaluate()` はページを読む (文言・URL・状態の確認) ためだけに使う。ストアや DOM を書き換えて入力を省かない (画面の入力を検証できなくなる)
  - 文字列をスクリプトに埋め込むときは `JSON.stringify` でリテラルにする
- 同じ view に操作を並べて投げない。種類ごとに同時に 1 つしか受け付けず、2 つ目はキューされずに `ERR_INVALID_STATE` で失敗する。必ず 1 つずつ `await` する
- 画面の確認が要る場面では `screenshot(view, name)` で `test-results/` に PNG を残す。Claude は PNG を読んで、レイアウト崩れなど文言では確かめられないことを確認する

## 方針

- 本物の API / DB / Mailpit を叩く。ネットワークのモック (CDP の `Fetch` での差し替えなど) は使わない
- テストデータはユニークなメールアドレス (`e2e-{timestamp}-{random}@example.com`) で分離する。DB の TRUNCATE / 事後クリーンアップはしない (並列・再実行に安全)
- 非同期経路 (検証メール配送 / テナント作成 = Pub/Sub) は、届くまで条件を繰り返し確かめて待つ
- 並行した再要求で検証トークン等が複数発行されうる経路では、届いたメールのトークンを新しい順に試して有効な 1 つを採用するヘルパーにする (最初の 1 通に決め打ちしない)。有効なトークンが無い状態への真に並行な再要求では、別々のトークンが発行されて片方が後勝ちで消えることがあり、決め打ちすると 401 のフレークになる
- メール plain text パートからリンク／トークンを抜くときは、行の折り返しを復元してから正規表現にかける。html2text 等の既定の折り返し (78 桁) はトークンの途中に改行を入れることがあり、途中で切れた無効なリンクを拾って 401 になり続けるフレークの原因になる。メールからリンクを抜くヘルパーは必ず折り返しの復元を通す (送信側も plain text を折り返さない設定にしておく)

## 実行

- `task dev:e2e` (compose 起動込み。`task dev:e2e -- e2e/authority/signup.spec.ts` で spec 指定)
- Mac 以外は Chrome が要る。Bun が自動で探し、別の場所にあるときは `BUN_CHROME_PATH` で指す
- 失敗したら、エラーに出る `test-results/*.png` を読んで原因を確かめてから直す
- CI: `.github/workflows/e2e-test.yml` がローカルと同じ `task dev:e2e` を実行し、失敗時は `test-results/` を artifact に保存する

## backend テストとの住み分け

- API 単体の仕様 (バリデーション / 権限 / エラー) は `backend/test/acceptance` (pytest) で検証する
- E2E は「画面 → API → DB → メール → 画面」を横断するユーザーフローのみに絞り、ケース数を増やしすぎない
