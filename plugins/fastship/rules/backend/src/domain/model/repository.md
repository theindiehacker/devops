---
description: リポジトリ (Repository) の設計/実装方法
summary: 1集約ルート=1リポジトリ。集約を出し入れし境界キー(pool_id/app_id)を引数で強制する。別モジュールの集約は import せず ACL 越しに読む
paths:
  - "backend/src/**/domain/model/**/*.py"
---
# リポジトリ (Repository)

集約の永続化を抽象化する。**1 集約ルートにつき 1 リポジトリ**。IF はドメイン層、実装はポート・アダプター層。

規範例:
 - IF（ドメイン層）: `backend/src/authority/domain/model/user/user_repository.py`（`UserRepository`）
 - 実装（ポート・アダプター層。PostgreSQL は 4 段構造）: `backend/src/authority/port/adapter/persistence/repository/`
   - `postgresql/user/postgresql_user_repository.py`（薄い委譲）→ `cache_layer_user.py`（キャッシュ）→ `driver_manager_user.py`（SQLAlchemy）→ `driver/*_table_row.py`（テーブル定義 + `to_entity()`）
   - `inmem/in_mem_user_repository.py`（テスト用）

## 実装規約

 - **IF は `abc.ABC`** で `domain/model/<集約>/<集約>_repository.py` に置く。集約と同ディレクトリ。
 - **メソッドは集約を出し入れする**: `next_identity()` / `add()` / `remove()` / `get(id)` と、必要なクエリメソッド。集約以外（DTO / 行）を返さない。
 - **境界キーを引数で強制する**: App データを引くクエリは `pool_id` を先頭引数に取る（実例 `user_with_email_address(pool_id, email)` / `user_with_token(pool_id, ...)`）。「ある名簿で登録したユーザーが別の名簿で引けてしまう」を型で塞ぐ第一防衛線（RLS が最終防衛線）。`tenant.Tenant` は `app_id` スコープ。
 - **実装は DI でプロファイル別に差し替え**る（`core.py` で `DI.of(UserRepository, {"InMem": InMem..., ...}, PostgreSQL...)`）。テストは `InMem` プロファイルで DB 無しに回す。
 - トランザクション境界は application 層の `@transactional` が持つ。リポジトリは UoW（`PostgreSQLUnitOfWork` 等）越しに読み書きする。

## 別モジュールの集約を読むとき（リポジトリを作らない）

リポジトリは**自集約**の永続化専用。別モジュールの集約（例: tenant から authority の `User`）を読むときは、リポジトリを作らず、その集約も import しない。
「相手コンテキストからドメインオブジェクトを取得する」のは**ファクトリとしてのドメインサービス（腐敗防止層＝ACL）**の役割 → `${CLAUDE_PLUGIN_ROOT}/rules/backend/src/domain/model/domain_service.md` を参照（4 点セット・命名・フォルダ構成・規範例）。

## アンチパターン

 - ❌ 集約以外（テーブル行 / DTO / プリミティブ）を返すリポジトリメソッド。
 - ❌ 境界キー（`pool_id` / `app_id`）を取らない App データのクエリ（別名簿・別 App のデータが漏れる）。
 - ❌ 別モジュールの集約を直接 import して読む（ACL 越しにする。import-linter が構造違反を機械検出）。
 - ❌ 1 集約ルートに複数リポジトリ / 複数集約を 1 リポジトリで扱う。

## CacheLayer の実装（PostgreSQL 4 段構造の 2 段目）

 - **`cache_layer_<集約>.py` は common の `CacheLayer[A]` を composition で持つ**（継承しない）。キー組み立て・nested `Translator`（`CacheLayer.Translator[T]` の具象）・driver 呼び出しの継ぎ合わせだけを書く。規範例: `backend/src/app/port/adapter/persistence/repository/postgresql/role/cache_layer_role.py`
 - **キーは `KeyNamespace` で鋳造する**: driver が `ControlUnitOfWork` 固定の集約（App 定義レジストリ）は `KeyNamespace.control()` + `KeyPolicy.CONTROL`、ルーティング UoW の集約（テナントデータ）は `KeyNamespace.APP/POOL.scoped()` + `KeyPolicy.SCOPED`。生 str でキーを組まない（mypy が弾く）。単軸キャッシュはコールサイトにインラインで書き、多軸キャッシュのみ private キーヘルパで read / fill / 書き込みのキー式を共有する。
 - **削除は 2 択**: 物理削除は `remove()`（SETEX tombstone。コミット前 DEL は再キャッシュ競合窓が開くため禁止）、論理削除は削除状態ペイロードの `set()`。物理 DEL（`clear`）はコミット後イベント購読側専用。
 - ❌ プロセスローカル dict のキャッシュ（多インスタンスで stale 永続）。❌ miss+None の negative cache。❌ 一覧・条件クエリのキャッシュ（driver へ素通しする）。
