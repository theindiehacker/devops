---
description: ドメインサービスの設計/実装方法（使いどころ + ファクトリとしての ACL / 腐敗防止層）
summary: ドメインサービスは最終手段。別コンテキストの概念は ACL(自コンテキストのセパレート IF＋翻訳アダプタ)越しに自前 read-model へ翻訳して読み、相手集約を import しない
paths:
  - "backend/src/**/domain/model/**/*.py"
  - "backend/src/**/port/adapter/service/**/*.py"
---
# ドメインサービス (Domain Service)

ドメインサービスとは、あるロジックを実現したいがエンティティ/値オブジェクト/集約/コンポジションに実装するのが不適切である場合に用いるものです。

 - 大抵のロジックは、エンティティ/値オブジェクト/集約/コンポジションのプロパティやメソッドとして実装できるので、ドメインサービスはなくても問題ありません
 - ドメインサービスを多用すると、次のような問題が発生します
   - プロパティだけのエンティティ/値オブジェクトが発生(ドメイン貧血症。`${CLAUDE_PLUGIN_ROOT}/rules/backend/src/domain/model/domain.md`)
   - ドメインサービスにロジックが集中し、バグの温床になる/テストコードが肥大化する
 - たとえば、「複数のエンティティ/値オブジェクト/集約/コンポジションをもとに計算するロジック」など、どうしてもエンティティや値オブジェクトなどで実装できない時や不適切である時にだけドメインサービスを導入しましょう

## ファクトリとしてのドメインサービス（境界付けられたコンテキストからドメインオブジェクトを取得するドメインサービス）

別の境界付けられたコンテキストが持つ概念を自コンテキストで使いたいとき、相手の集約やリポジトリを直接触らない。
**「相手コンテキストからドメインオブジェクトを取り出す」責務を、自コンテキストのドメインサービス（＝ファクトリ）として表す**。
これはリポジトリ（自集約の永続化。1 集約ルート = 1 リポジトリ。`${CLAUDE_PLUGIN_ROOT}/rules/backend/src/domain/model/repository.md`）ではない ―― 返すのは相手の集約ではなく、翻訳済みの**自コンテキストの read-model** だからだ。

 - **セパレートインターフェースによるドメインサービス**: 「相手の情報が要る」という*要求*はドメインの語彙なので、IF（`abc.ABC`）は自コンテキストの **domain 層**に置く（例 `UserDatabaseService` / `AppDatabaseService`）。「どう取ってくるか」（相手の公開 Resource を叩く）はインフラの都合なので実装は **port/adapter 層**へ分離する（＝セパレートインターフェース）。domain 層は相手モジュールを import せず、IF と自前 read-model だけを見る。
 - **腐敗防止層 = アダプター + トランスレーター**: 実装側は、相手コンテキストの語彙が自コンテキストに漏れ込むのを防ぐ ACL になる。
   - **アダプター**: 相手の**公開 Resource**（`AppResource` 等）を呼び、型付き応答（`AppJson` / `UserJson` 等）を受け取る。相手の内部集約ではなく公開 IF だけに依存する。
   - **トランスレーター**: その型付き応答を**自コンテキストの read-model 値オブジェクトへ写像**し、相手の語彙を自分の意図に翻訳する（例: `app` の `mode="b2b"` → `tenant` の「新規登録で契約企業を作るか」）。**同じ App 概念でもコンテキストごとに read-model が違う**のが要諦。
 - 返す read-model は相手の集約とは**別物の「自コンテキストのユビキタス言語にある値オブジェクト」**。

規範例:
 - App 設定読み取り: `authority/domain/model/app/app_database_service.py`（IF）→ `authority/port/adapter/service/app/adapter/app.py`（`AppAdapter`）。同型が `tenant` / `apigateway` にもある。
 - User 読み取り: `tenant/domain/model/user/user_database_service.py`（IF）→ `tenant/port/adapter/service/user/adapter/authority.py`（`AuthorityAdapter` + `AuthorityTranslator`）。
 - トークン認証: `apigateway/domain/model/user/identity_access_service.py`（`IdentityAccessService`）→ `apigateway/port/adapter/service/user/adapter/authority.py`。**命名は `_database_service` に限らない**（サービス名はユビキタス言語で付ける。dir は `user` だがサービス名は `identity_access`）。

フォルダ構成（抽象は domain/、実装は port/adapter/の 4 点セット。`<x>` = 概念名（dir / VO。例 user・app）、`<svc>` = サービス名（ユビキタス言語。例 user_database・identity_access）。両者は一致しなくてよい）:
```
backend/src/<module>/
├── domain/model/<x>/                     ← 抽象（ドメイン層）
│   ├── <svc>_service.py                  #   セパレート IF（abc.ABC）
│   └── <x>.py                            #   自前 read-model VO（相手集約は import しない）
└── port/adapter/service/<x>/             ← 実装（ポート・アダプター層）
    ├── <svc>_service_impl.py             #   Service 実装（DI で adapter を注入し委譲するだけ）
    └── adapter/
        ├── <svc>_adapter.py              #   二次抽象（Adapter IF、DI 差し替え口）
        ├── <相手module>.py                #   翻訳アダプタ（アダプター + トランスレーター）
        └── stub.py                       #   テスト用スタブ（単体テストの差し替え）
```
※ 末尾は `_service`（`Service`）で終えるのが規約。`<svc>` は自コンテキストのユビキタス言語で命名し、`<x>`（概念名）に縛られない ―― 実例 `user_database_service.py` / `app_database_service.py` / `identity_access_service.py`（最後の 1 つは dir が `user` でもサービス名は `identity_access`）。`database` は必須ではなく、`authority` を「ユーザーデータベース」と捉えた命名（将来ユーザー管理を Auth0 / Clerk / CDP へ委譲する余地を含意）。
※ `stub.py`（テスト用スタブ）は**テストコードでなくプロダクションコードに置く**（`${CLAUDE_PLUGIN_ROOT}/rules/backend/test/test.md` の「ドメインサービスのスタブはテストコードでは定義しない」）。
