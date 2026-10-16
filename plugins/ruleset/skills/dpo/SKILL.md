---
name: dpo
description: DPO クラスの実装方法。DPO の生成には集約のみを渡す。プリミティブや他 DPO をフィールドに持たせない
paths:
  - "backend/src/**/application/**/dpo.py"
user-invocable: false
---
# DPO (Data Payload Object)
## 実装方法
DPO クラスでは複数の集約ないしは単一の集約インスタンスを DPO クラスに指定できるように実装してください。

### 生成には集約を指定すること
DPOクラスの生成には集約を指定してください。それ以外は指定しないでください。

Bad:
```python
# 集約以外を指定している
@dataclass(init=True, unsafe_hash=True, frozen=True)
class UserDpo:
    name: str
    email_address: str
    tenant_name: str | None
    tenant_id: int | None
    ...

# 他DPO を指定している
@dataclass(init=True, unsafe_hash=True, frozen=True)
class OtherDpo:
    ...

@dataclass(init=True, unsafe_hash=True, frozen=True)
class MainDpo:
    others: tuple[OtherDpo, ...]
```

Good:
```python
from hoge.domain.model.user import User
from hoge.domain.model.tenant import Tenant
from hoge.domain.model.other import Other

@dataclass(init=True, unsafe_hash=True, frozen=True)
class UserDpo:
    user: User  # 集約クラスを指定
    tenant: Tenant | None


@dataclass(init=True, unsafe_hash=True, frozen=True)
class OtherDpo:
    ...

@dataclass(init=True, unsafe_hash=True, frozen=True)
class MainDpo:
    others: tuple[Other, ...]

    def __iter__(self) -> OtherDpo:
        # UI層で操作が必要な場合は、戻り値が DPO となる __iter__ やプロパティを提供すること
        ...
```

### 例外: トークン生成 DPO（トークン VO + `Secret`）

JWT 等の署名トークンを発行する DPO は、集約ではなく **トークン VO（または署名対象の read-model）+ `Secret`** から
構成してよい。このフローには UI 描画のための集約が登場せず、DPO の責務が「payload を秘密鍵で署名して JWT
文字列にする（`generate_jwt()`）」ことに閉じるため（集約を無理に受けさせない）。実例（同型）:

```python
# InternalTokenDpo = UserToken + Secret（ManagementTokenDpo = ManagementToken + Secret も同じ形）
@dataclass(init=True, unsafe_hash=True, frozen=True)
class InternalTokenDpo:
    __internal_token: UserToken
    __secret: Secret

    def generate_jwt(self) -> str:
        return jwt.encode(self.__internal_token.payload, self.__secret.value, algorithm="RS256")


# AppDpo = App(read-model) + Secret。AppToken は generate_jwt() 内で生成して署名する
@dataclass(init=True, unsafe_hash=True, frozen=True)
class AppDpo:
    app: App
    __secret: Secret

    def generate_jwt(self) -> str:
        # typ ヘッダで種別を明示し、内部トークン (typ 無し) や management トークン (mgmt+jwt) と誤受理し合わない
        return jwt.encode(AppToken.generate(from_=self.app).payload, self.__secret.value,
                          algorithm="RS256", headers={"typ": APP_INTERNAL_TOKEN_TYPE})

    def to_current_app(self) -> CurrentApp:
        return CurrentApp(app_id=self.app.id, pool_id=self.app.user_pool_id)
```

### メソッド

集約から導出できる値（URL 等）は、フィールドに生値で持たせず、**集約へ委譲する DPO のメソッド**として
提供する（`base_domain` 等のインフラ設定は引数で受け、未指定時のみ設定から補う）。

```python
@dataclass(frozen=True)
class ResolvedAppDpo:
    """host / slug から解決した App と所属 User Pool。

    公開ホスト URL は「導出の正」である App 集約 (`App.front_base_url` / `issuer`) へ委譲する
    メソッドとして提供し、DPO 自体は集約のみを保持する。
    """

    app: App
    user_pool: UserPool

    def front_base_url(self, base_domain: str | None = None) -> str:
        """App の公開フロントホスト URL。App 集約 (`App.front_base_url`) へ委譲する。"""
        return self.app.front_base_url(base_domain or AppSettings.instance().base_domain)

    def issuer(self, base_domain: str | None = None) -> str:
        """App の OAuth 2.1 AS issuer。App 集約 (`App.issuer`) へ委譲する。"""
        settings = AppSettings.instance()
        return self.app.issuer(base_domain or settings.base_domain, settings.oauth_issuer)
```

## 実装例

単一集約の DPO と、その集合を `__iter__` で単一 DPO として返す DPO:

```python
@dataclass(init=True, unsafe_hash=True, frozen=True)
class UserDpo:
    user: User


@dataclass(init=True, unsafe_hash=True, frozen=True)
class UsersDpo:
    users: set[User]

    def __iter__(self) -> Generator[UserDpo]:
        for user in self.users:
            yield UserDpo(user)
```

複数の集約を詰める DPO（UI 層で要るプリミティブは集約へ委譲するメソッドで返す）:

```python
@dataclass(init=True, unsafe_hash=True, frozen=True)
class TenantDpo:
    tenant: Tenant
    projects: list[Project]

    def tenant_id(self) -> str:
        """テナント ID をプリミティブで返す (集約へ委譲する導出値)。"""
        return self.tenant.id.value

    def member_role_of(self, user_id: str) -> str | None:
        role = self.tenant.member_role_of(UserId(user_id))
        return role.name if role else None
```
