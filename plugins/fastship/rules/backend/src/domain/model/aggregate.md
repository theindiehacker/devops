---
description: 集約・エンティティの設計/実装方法
summary: 集約は1トランザクション=1整合性境界。他集約は ID 値オブジェクトで参照し内包しない。不変条件は集約メソッドで守り生成は静的ファクトリ。1Tx で複数集約を更新しない
paths:
  - "backend/src/**/domain/model/**/*.py"
---
# 集約 (Aggregate) / エンティティ

集約は **1 トランザクション = 1 整合性境界**。「同時に必ず整合していなければならないオブジェクトの塊」を 1 つの集約にまとめ、集約ルート経由でのみ操作する。

規範例（迷ったらこれを読んで写す）:
 - `backend/src/authority/domain/model/user/user.py`（User 集約）
 - `backend/src/tenant/domain/model/tenant/tenant.py`（Tenant 集約）

## 境界の切り方（判断ヒューリスティック）

 - **不変条件で切る**: 「この 2 つは常に同時に正しくないと壊れる」なら同じ集約。「結果整合で良い」なら別集約 + イベント連携。
 - **1 集約 = 1 リポジトリ = 1 トランザクション**。1 ユースケースで複数集約を更新したくなったら、境界が間違っているか、**プレーン/集約を跨ぐ副作用をドメインイベントにすべき**サイン（`${CLAUDE_PLUGIN_ROOT}/rules/backend/src/domain/model/domain-event.md`）。
 - **集約は小さく保つ**。「参照したいから」で内包しない。参照は下記の ID 値オブジェクトで持つ。
 - 迷ったら「トランザクション境界はどこか」を先に決める。それが集約境界。

## 他集約は "ID 値オブジェクト" で参照する（オブジェクトを内包しない）

 - 他集約のインスタンスをフィールドに持たない。**ID 値オブジェクト（`UserId` / `AppId` / `PoolId` 等）で参照**する。
 - 別モジュールの集約が必要なときは import せず、ACL（腐敗防止層）越しに読む（`${CLAUDE_PLUGIN_ROOT}/rules/backend/src/domain/model/domain_service.md`、実例 `AuthorityAdapter`）。
 - import-linter がモジュール跨ぎの内部 import を機械的に禁止しているので、構造違反は `task style:check` で落ちる。

## 実装規約

 - `@dataclass(init=True, eq=False)` とし、**同一性は ID で判定**する（`__eq__` / `__hash__` を `id` ベースで実装）。値等価にしない。
 - **生成は静的ファクトリメソッド**（例: `User.provision(...)` / `Tenant.provision(...)`）。`__init__` を業務語彙にせず、ファクトリ名にユビキタス言語の動詞を使う。
 - **不変条件は集約メソッド内で守る**。「リセットは PASSWORD_RESET トークンのみ」「最後の連携は解除不可」のように、壊れた状態を作らせないガードをメソッドに書く（規範例 `user.py` の `reset_password` / `unlink`）。リポジトリ側のスコープと二重になっても、集約単体を最終防衛線にする。
 - **状態変化はドメインイベントを publish** する: `DomainEventPublisher.instance().publish(...)`（実例 `user.py` の `provision` / `generate`）。プレーンを跨ぐ副作用はイベントに寄せる。
 - **ドメインサービスが要るロジックは集約内から `DomainRegistry.resolve(IF)`** で解決する（例: `user.py` の `protect_password` が `EncryptionService` を解決）。application 層に IF を渡させない。

## アンチパターン（レビューで弾く / `anemic-domain-model` の芽）

 - ❌ ゲッター/セッターとプロパティだけで**振る舞いメソッドが無い**集約（= ドメイン貧血症）。ユビキタス言語の動詞は集約メソッドになる（`${CLAUDE_PLUGIN_ROOT}/rules/backend/src/domain/model/domain.md`）。
 - ❌ アプリケーションサービスが集約のフィールドを直接書き換えて不変条件を組み立てている（ロジック漏れ）。その手続きは集約メソッドに引き上げる。
 - ❌ 他集約インスタンスを内包している（ID 参照にする）。
 - ❌ 1 トランザクションで複数集約を更新している（境界の誤り or イベント化漏れ）。
