---
description: ドメインイベントの設計/実装方法
summary: 集約/プレーンを跨ぐ副作用はドメインイベントで伝播する。過去形で命名し to_dict はプリミティブのみ。発行は集約メソッド内で行い application 層から publish しない
paths:
  - "backend/src/**/domain/model/**/*.py"
---
# ドメインイベント (Domain Event)

**集約/プレーンを跨ぐ副作用はドメインイベントで伝播する**（1 トランザクションに閉じ込めない）。「起きた事実」を過去形で表す。

基底・規範例:
 - 基底: `backend/src/common/domain/model/domain_event.py`（`DomainEvent` / `DomainEventPublisher` / `DomainEventSubscriber` / `ProcessingPlane`）
 - イベント実装: `backend/src/authority/domain/model/user/user_provisioned.py`（`UserProvisioned`）、`verification_token_generated.py`
 - 購読側（別モジュール）: `backend/src/notify/port/adapter/messaging/verification_token_generated_listener.py`

## いつイベントにするか

 - **プレーンを跨ぐ副作用**（Control ↔ App、例: App 作成 → App プレーンへのスコープ provision）は必ずイベント。単一トランザクションにしない（`CLAUDE.md`「プレーンをまたぐ副作用はドメインイベント」）。
 - **別集約/別モジュールへの波及**（ユーザー登録 → 検証メール送信 = notify モジュール）はイベント。呼び出し側は購読側を知らない。
 - **横断集計**（手数料・売上のような別プレーンへの射影）はイベントで射影を作る。App DB を横断クエリしない。
 - 逆に、同一集約内で閉じる整合はイベントにしない（メソッドで同期的に守る）。

## 実装規約

 - **過去形で命名**する（`UserProvisioned` / `VerificationTokenGenerated` / `MemberInvited`）。命令形にしない。
 - `DomainEvent` を継承し、`__init__` で `super().__init__(event_version, occurred_on)` → `super().__setattr__(...)` で属性設定（frozen なため）。
 - **`to_dict()` はプリミティブのみ**返す（MQ ペイロード）。ID 値オブジェクトは `.value` に落とす（実例 `user_provisioned.py`）。集約インスタンスを載せない。
 - **発行は集約メソッド内**から `DomainEventPublisher.instance().publish(...)`（application 層から publish しない。状態変化の事実と発行を同じ場所に置く）。
 - **発生元と別プレーンで処理させたい場合のみ** `processing_plane()` を override して `ProcessingPlane(app_id, pool_id)` を返す（既定 `None` = 発生元プレーンで処理）。override すると全購読者が申告先で処理される点に注意（詳細は基底の docstring）。
 - 購読は `port/adapter/messaging/*_listener.py` に置く（ドメイン層に購読側を書かない）。

## アンチパターン

 - ❌ プレーン/集約跨ぎの更新を 1 トランザクションで同期実行（イベント化漏れ）。
 - ❌ `to_dict()` に VO やエンティティをそのまま入れる（プリミティブに落とす）。
 - ❌ application サービスからイベントを publish する（集約メソッドに寄せる）。
 - ❌ 現在形・命令形のイベント名（`CreateUser` 等）。
