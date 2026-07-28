---
description: DPO クラスの実装方法
summary: DPO の生成には集約のみを渡す。プリミティブや他 DPO をフィールドに持たせない
paths:
  - "backend/src/**/application/**/dpo.py"
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

 - `backend/src/apigateway/application/authentication/dpo.py`（`InternalTokenDpo` = `UserToken` + `Secret`）
 - `backend/src/apigateway/application/management/dpo.py`（`ManagementTokenDpo` = `ManagementToken` + `Secret`）
 - `backend/src/apigateway/application/app/dpo.py`（`AppDpo` = `App`(read-model) + `Secret`。`AppToken` は `generate_jwt()` 内で生成して署名）

### メソッド

集約から導出できる値（URL 等）は、フィールドに生値で持たせず、**集約へ委譲する DPO のメソッド**として
提供する（例: `backend/src/app/application/resolve/dpo.py` の `ResolvedAppDpo.front_base_url()` /
`issuer()` が `App.front_base_url()` / `App.issuer()` へ委譲。`base_domain` 等のインフラ設定は
引数で受け、未指定時のみ設定から補う）。

## 実装例

 - backend/src/authority/application/identity/dpo.py
 - backend/src/apigateway/application/app/dpo.py
 - backend/src/tenant/application/tenant/dpo.py