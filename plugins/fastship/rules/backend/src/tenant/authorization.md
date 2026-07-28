---
description: テナントスコープのルートの認可・アドレッシング規約
summary: テナント ID はパスパラメータで受け、認可はトークンの membership 突合で判定する。非メンバーは 404 で存在を伏せ、権限不足のメンバーは 403。所属ゼロも fail-close。RLS 境界は pool_id / owner_tenant_id
paths:
  - "backend/src/tenant/port/adapter/resource/**/*.py"
  - "backend/src/common/port/adapter/resource/dependency/**/*.py"
---
# テナントの認可・アドレッシング (secure-by-default)

テナント ID は `/tenants/{tenant_id}/...` の**パスパラメータで受ける**。サブドメイン
(`{tenant}.{AppId}...`) やヘッダ (`X-Tenant-Id`) には**載せない**。

## 認証・認可依存 (Depends) の使い分け

`common/port/adapter/resource/dependency/` は実行主体 (actor) の種類ごとにモジュールを分けている。
**迷ったらまず `GetCurrentUser`**（認証 + テナントスコープ認可込み）。

| 依存 | credential | 使う場面 |
|:--|:--|:--|
| `GetCurrentUser(permit)` | 内部通信用トークン | 既定。path の `tenant_id` と membership を突合して認可まで行う |
| `GetAuthenticatedUser` | 内部通信用トークン | 認可の証跡が membership 以外（招待コード等）にあるルートだけ。認証（署名検証）のみ |
| `GetManagementActor` | management トークン (act-as-app) | リクエストの App が system ではなく**対象 App** の管理ルートだけ。コンソール操作者の越境実行主体を返す |
| `GetCurrentApp` | App 内部トークン (x-app-internal-token) | 匿名可のルート含め App コンテキスト（app_id / pool_id）が要る Resource。ResolveAppMiddleware が全リクエストで発行するトークンを検証する |

- 新しい actor（例: 運営スタッフ = `operator:*`）を足すときは既存クラスにフラグを生やさず、
  **actor ごとに新モジュール + 依存クラス**を追加する。
- 「App コンテキスト（app_id / pool_id）が欲しい」は専用の **App 内部トークン (`x-app-internal-token`)** を
  `GetCurrentApp` で読む。**user 認証トークン (`x-internal-token`) / management トークンには App ペイロードを
  載せない**（実行主体ごとに credential を分ける。混載は ACL 翻訳の設計を崩す）。App 内部トークンは
  `ResolveAppMiddleware` が全リクエスト（匿名含む）で発行する **ACL 翻訳済みの公開スキーマ・スナップショット**
  で、正（クレーム契約）は `AppToken.generate()`（`backend/src/apigateway/domain/model/token/internal/internal_token.py`）とそのユニットテスト。
- 「App **設定**（デザイントークン等の可変長・非スナップショット項目）が欲しい」は各コンテキストの ACL
  (`AppDatabaseService` 系) 経由で読む（可変長設定はトークンに載せない。理由: ヘッダサイズを有界に保つ +
  コンテキストごとに翻訳する）。`mode` 等の固定値スナップショットは `app` クレーム（`AppToken`）に載せてよい。

## なぜパスパラメータか（サブドメイン/ヘッダにしない理由）

置き場所を変えても安全性は上がらない ― パス・サブドメイン・ヘッダのどれもクライアントが
書き換えられる入力で、防御は「受け取った後の検証」に閉じる（BOLA/IDOR 対策）。加えて:

 - **サブドメイン**: サブドメインは AppId 解決に既に使用（`{AppId}.api.fastship.jp`）。テナントを
   足すとサブサブドメインになり、ワイルドカード証明書 1 ラベル制約で不可（`CLAUDE.md` 確定方針）。
   App テナントは実行時に無制限に増えるため DNS/証明書運用も成立しない。
 - **ヘッダ**: 得るものが無く、キャッシュ汚染・ログ/監査でのテナント不可視・生成クライアントの
   指定漏れを招く。業界標準（GitHub `/orgs/{org}` / GCP / Auth0）もパス方式。

## 認可の実装規約（多層防御）

 1. **第一防衛線 = resource の依存ゲート**: テナントスコープのルートは
    `Depends(GetCurrentUser({...}))` を必ず付ける。`CurrentUser.access_to(tenant_id, permit)` が
    トークンの `tenants` メンバーシップとパスの `tenant_id` を突合して判定する。
 2. **フェイルクローズ**: 所属テナントゼロ（`tenants` クレームが空 → `None`）のユーザーは
    **非メンバー扱いで拒否**する（素通しさせない）。テナントスコープのルートで「テナント概念が無いから
    許可」という分岐を作らない。
 3. **ステータスの出し分け**: **非メンバーは 404**（`tenant_id` の実在を漏らさない = 存在オラクルを
    塞ぐ。レスポンスに `tenant_id` を含めない）。**メンバーだがロール不足は 403**。
    `TenantAccess`（`ALLOWED` / `NOT_A_MEMBER` / `FORBIDDEN`）で区別する。
 4. **第二防衛線 = サービス層の再検証**: 参照系（`members()` / `list()`）も書き込み系と同様に
    アプリケーションサービスで所属を再検証し、resource の依存ゲート単層に依存しない。

## RLS との関係

テナント間隔離は**アプリ層の認可境界**（同一 App DB 内の全テナントは同じ契約企業の App データ）。
DB の RLS 境界は `pool_id`（App データ）/ `owner_tenant_id`（Control）で、`tenant_id` 単位の RLS は
**張らない**（トークン発行は 1 ユーザーの全テナントのメンバーシップを横断読みし、`GET /tenants` も
横断参照するため、`tenant_id` を GUC で絞ると正当な横断読みが壊れる。既存 `enable_rls_app_isolation`
マイグレーションの除外理由と同じ）。
