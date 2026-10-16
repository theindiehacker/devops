---
name: repository
description: リポジトリ (Repository) の設計/実装方法。1集約ルート=1リポジトリ。集約を出し入れし境界キー(pool_id/app_id)を引数で強制する。別モジュールの集約は import せず ACL 越しに読む
paths:
  - "backend/src/**/domain/model/**/*.py"
user-invocable: false
---
# リポジトリ (Repository)

集約の永続化を抽象化する。**1 集約ルートにつき 1 リポジトリ**。IF はドメイン層、実装はポート・アダプター層。

構成（`<module>/port/adapter/persistence/repository/` 配下。コードは末尾の「規範例」節）:
 - IF（ドメイン層）: `domain/model/<集約>/<集約>_repository.py`（例 `UserRepository`）
 - 実装（ポート・アダプター層。PostgreSQL は 4 段構造）:
   - `postgresql/<集約>/postgresql_<集約>_repository.py`（薄い委譲）→ `cache_layer_<集約>.py`（キャッシュ）→ `driver_manager_<集約>.py`（SQLAlchemy）→ `driver/*_table_row.py`（テーブル定義 + `to_entity()`）
   - `inmem/in_mem_<集約>_repository.py`（テスト用）

## 実装規約

 - **IF は `abc.ABC`** で `domain/model/<集約>/<集約>_repository.py` に置く。集約と同ディレクトリ。
 - **メソッドは集約を出し入れする**: `next_identity()` / `add()` / `remove()` / `get(id)` と、必要なクエリメソッド。集約以外（DTO / 行）を返さない。
 - **境界キーを引数で強制する**: App データを引くクエリは `pool_id` を先頭引数に取る（実例 `user_with_email_address(pool_id, email)` / `user_with_token(pool_id, ...)`）。「ある名簿で登録したユーザーが別の名簿で引けてしまう」を型で塞ぐ第一防衛線（RLS が最終防衛線）。`tenant.Tenant` は `app_id` スコープ。
 - **実装は DI でプロファイル別に差し替え**る（モジュールの `core.py` で登録する）。テストは `InMem` プロファイルで DB 無しに回す。
   ```python
   DI.of(UserRepository, {"InMem": InMemUserRepository}, PostgreSQLUserRepository),
   ```
 - トランザクション境界は application 層の `@transactional` が持つ。リポジトリは UoW（`PostgreSQLUnitOfWork` 等）越しに読み書きする。

## 別モジュールの集約を読むとき（リポジトリを作らない）

リポジトリは**自集約**の永続化専用。別モジュールの集約（例: tenant から authority の `User`）を読むときは、リポジトリを作らず、その集約も import しない。
「相手コンテキストからドメインオブジェクトを取得する」のは**ファクトリとしてのドメインサービス（腐敗防止層＝ACL）**の役割 → `ruleset:domain-service` skill を参照（4 点セット・命名・フォルダ構成・規範例）。

## アンチパターン

 - ❌ 集約以外（テーブル行 / DTO / プリミティブ）を返すリポジトリメソッド。
 - ❌ 境界キー（`pool_id` / `app_id`）を取らない App データのクエリ（別名簿・別 App のデータが漏れる）。
 - ❌ 別モジュールの集約を直接 import して読む（ACL 越しにする。import-linter が構造違反を機械検出）。
 - ❌ 1 集約ルートに複数リポジトリ / 複数集約を 1 リポジトリで扱う。

## CacheLayer の実装（PostgreSQL 4 段構造の 2 段目）

 - **`cache_layer_<集約>.py` は common の `CacheLayer[A]` を composition で持つ**（継承しない）。キー組み立て・nested `Translator`（`CacheLayer.Translator[T]` の具象）・driver 呼び出しの継ぎ合わせだけを書く。規範例: 末尾の `CacheLayerRole`
 - **キーは `KeyNamespace` で鋳造する**: driver が `ControlUnitOfWork` 固定の集約（App 定義レジストリ）は `KeyNamespace.control()` + `KeyPolicy.CONTROL`、ルーティング UoW の集約（テナントデータ）は `KeyNamespace.APP/POOL.scoped()` + `KeyPolicy.SCOPED`。生 str でキーを組まない（mypy が弾く）。単軸キャッシュはコールサイトにインラインで書き、多軸キャッシュのみ private キーヘルパで read / fill / 書き込みのキー式を共有する。
 - **削除は 2 択**: 物理削除は `remove()`（SETEX tombstone。コミット前 DEL は再キャッシュ競合窓が開くため禁止）、論理削除は削除状態ペイロードの `set()`。物理 DEL（`clear`）はコミット後イベント購読側専用。
 - ❌ プロセスローカル dict のキャッシュ（多インスタンスで stale 永続）。❌ miss+None の negative cache。❌ 一覧・条件クエリのキャッシュ（driver へ素通しする）。

## 規範例

### IF（ドメイン層）

```python
class UserRepository(abc.ABC):
    @abc.abstractmethod
    def next_identity(self) -> UserId:
        pass

    @abc.abstractmethod
    def add(self, user: User) -> None:
        pass

    @abc.abstractmethod
    def remove(self, user: User) -> None:
        pass

    @abc.abstractmethod
    def get(self, user_id: UserId) -> User | None:
        pass

    @abc.abstractmethod
    def user_with_token(self, pool_id: PoolId, token_type: Token.Type, value: str) -> User | None:
        pass

    @abc.abstractmethod
    def users_with_ids(self, *user_id: UserId) -> set[User]:
        pass

    @abc.abstractmethod
    def user_with_email_address(self, pool_id: PoolId, email_address: EmailAddress) -> User | None:
        pass

    @abc.abstractmethod
    def user_with_account(self, pool_id: PoolId, provider: Account.Provider, provider_account_id: str) -> User | None:
        pass
```

### PostgreSQL 実装（4 段構造）

1 段目のリポジトリは CacheLayer へ委譲するだけ。

```python
class PostgreSQLUserRepository(UserRepository):

    @inject
    def __init__(self, cache_layer_user: CacheLayerUser):
        self.__cache_layer_user = cache_layer_user

    @override
    def next_identity(self) -> UserId:
        return UserId(str(uuid.uuid4()))

    @override
    def add(self, user: User) -> None:
        self.__cache_layer_user.set(user)

    @override
    def remove(self, user: User) -> None:
        self.__cache_layer_user.delete(user)

    @override
    def get(self, user_id: UserId) -> User | None:
        return self.__cache_layer_user.cache_or_origin(user_id)

    @override
    def user_with_email_address(self, pool_id: PoolId, email_address: EmailAddress) -> User | None:
        return self.__cache_layer_user.cache_or_origin_with_email_address(pool_id, email_address)

    ...
```

2 段目の CacheLayer（common の `CacheLayer[A]` を composition で持つ形）:

```python
@singleton
class CacheLayerRole:
    """ロール定義の Redis 共有キャッシュ層 (common の CacheLayer 部品を composition で持つ)。

    by_id を read-through、`set` を write-through (LWW)、`remove` を tombstone で反映する。
    app_id 逆引き一覧 / 名前引きは境界スコープの複数行・条件クエリで by_id キャッシュとは別物のため
    driver に委譲する。ロール定義は App を定義する control プレーンのレジストリのため、CurrentApp 非依存の
    KeyNamespace.control (KeyPolicy.CONTROL) を使う。
    """

    class Translator(CacheLayer.Translator[Role]):
        """Role ⇔ JSON。"""

        def serialize(self, role: Role) -> str:
            payload: dict[str, Any] = {
                "id": role.id.value,
                "app_id": role.app_id.slug,
                "name": role.name,
                "permissions": sorted(permission.value for permission in role.permissions),
            }
            return json.dumps(payload)

        def deserialize(self, raw: str) -> Role:
            payload: Any = json.loads(raw)
            if not isinstance(payload, dict):
                raise TypeError("CacheLayerRole payload must be a JSON object")
            return Role(
                id=RoleId(payload["id"]),
                app_id=AppId.of(payload["app_id"]),
                name=payload["name"],
                permissions=frozenset(Permission(v) for v in payload["permissions"]),
            )

    # 60秒 x 15分。設定更新の反映遅延の上限。
    __TTL_SECONDS: ClassVar[int] = 60 * 15

    @inject
    def __init__(self, driver_manager_role: DriverManagerRole, redis_registry: RedisRegistry):
        self.__driver_manager_role = driver_manager_role
        self.__cache = CacheLayer[Role](
            redis_registry, self.Translator(), KeyPolicy.CONTROL, ttl_seconds=self.__TTL_SECONDS,
        )

    def cache_or_origin(self, role_id: RoleId) -> Role | None:
        return self.__cache.get_or_load(
            KeyNamespace.control(f"role:by_id:{role_id.value}"),
            lambda: self.__driver_manager_role.find_by_id(role_id),
        )

    def set(self, role: Role) -> None:
        self.__driver_manager_role.upsert(role)
        self.__cache.set(role, KeyNamespace.control(f"role:by_id:{role.id.value}"))

    def remove(self, role: Role) -> None:
        self.__driver_manager_role.delete(role.id)
        self.__cache.remove(KeyNamespace.control(f"role:by_id:{role.id.value}"))

    def roles_with_app(self, app_id: AppId) -> list[Role]:
        # 一覧・条件クエリはキャッシュせず driver へ素通しする
        return self.__driver_manager_role.find_by_app_id(app_id)
```

3 段目の DriverManager と 4 段目の TableRow（境界キー `pool_id` で絞り、行は `to_entity()` で集約に戻す）:

```python
@set_logger
class DriverManagerUser:
    @inject
    def __init__(self, unit_of_work: UnitOfWork) -> None:
        self.__unit_of_work: PostgreSQLUnitOfWork = unit_of_work  # type: ignore[assignment]

    def find_by_email_address(self, pool_id: PoolId, email_address: EmailAddress) -> User | None:
        with self.__unit_of_work.query() as q:
            optional: UsersTableRow | None = q.query(UsersTableRow)\
                .filter_by(pool_id=pool_id.value, email_address=email_address.text, deleted=False)\
                .one_or_none()
            return optional.to_entity() if optional else None

    def upsert(self, user: User) -> None:
        exists = self.__unit_of_work.session().query(UsersTableRow).filter_by(id=user.id.value).exists()
        if self.__unit_of_work.session().query(exists).scalar():
            self.update(user)
        else:
            self.insert(user)

    ...


class UsersTableRow(DataBase):
    __tablename__ = "users"
    ...

    def to_entity(self) -> User:
        return User(
            id=UserId(self.id),
            pool_id=PoolId(self.pool_id),
            username=self.username,
            image=URL(f"{AppSettings.instance().cdn_http_host}/{self.image}") if self.image else None,
            email_address=EmailAddress(self.email_address),
            encrypted_password=self.password,
            tokens=Tokens(frozenset(tr.to_value() for tr in self.tokens)),
            accounts={tr.to_value() for tr in self.accounts},
            verified_at=self.verified_at,
            enable=self.enable,
        )
```

### InMem 実装（テスト用）

InMem でも境界キー（`pool_id`）で絞る。

```python
class InMemUserRepository(UserRepository):
    def __init__(self) -> None:
        self.users: set[User] = set()

    @override
    def next_identity(self) -> UserId:
        return UserId(str(uuid.uuid4()))

    @override
    def add(self, user: User) -> None:
        self.users.add(user)

    @override
    def user_with_email_address(self, pool_id: PoolId, email_address: EmailAddress) -> User | None:
        for user in self.users:
            if user.pool_id == pool_id and user.email_address == email_address:
                return user
        return None

    ...
```
