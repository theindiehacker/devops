---
description: ユニットテストと受入テストの実装方法とルール
summary: テストは仕様書として上から順に読めるように書く。定数を使わずハードコード、テストクラス内のプライベートや継承基底クラスを作らない。ドメインサービスのスタブはプロダクションコードに置く
paths:
  - "backend/test/unit/**/*.py"
  - "backend/test/acceptance/**/*.py"
---
# ユニットテストと受入テストの実装方法/ルール
## 🏁 指針

 - テストコードが「(対象クラス/メソッドの)仕様書」として開発者が理解できるように実装してください。

## ✏️ 書き方
### ユニットテスト(UT)

 - ファイル名: `test_{テスト対象ファイル名}.py`
 - メソッドの命名:
   - 正常系メソッド: `~できる` / `~できない` / `~される` / `~されない` というように何ができる・できないのかがわかるように簡潔に命名してください
   - 異常系メソッド: どのようなとき / 条件で何の例外が送出されるのかがわかるようにしてください

```python
class Test{テスト対象クラス}:
    class Test_生成について:
        # __init__ のテスト
        def test_〇〇指定で生成できる(self) -> None:
            # 正常系メソッド
            ...
    
        def test_〇〇は{例外}を送出する(self) -> None
            # 異常系メソッド
            ...
    
    class Test_{テスト対象メソッド名}メソッドについて:
        def test_〇〇できる(self) -> None:
            ...

        def test_〇〇される(self) -> None:
            ...
```

### 受け入れテスト(Acceptance)

 - ファイル名: `test_{テスト対象API名}API.py`
 - メソッドの命名: メソッドがそのAPIの機能項目として理解できるように命名します
   - 正常系メソッド: `~できる` / `~できない` / `~される` / `~されない` というように**非エンジニア(PMを想定)**でも「何ができる・できない」のかがわかるように簡潔に命名してください
   - 異常系メソッド: どのようなとき / 条件で何の例外が送出されるのかがわかるようにしてください

```python
class Test_{APIの名前}API:
    def test_〇〇できる(self, client: TestClient, ...) -> None:
        ...
```

---
## 📚 ルール
### 定数は利用しない
定数を利用すると、開発者がその都度「この定数にはどんな値があるのか？」とスクロールして確認する手間が発生します。テストコードが「テスト対象コードの仕様書」として上から順に可読できるようにハードコードにしてください。

Bad:
```python
email_address = EmailAddress(EMAIL_ADDRESS_TEST)
```

Good:
```python
email_address = EmailAddress("tamura.taiyo@example.com")
```

### プライベートクラス(もしくはそれに準ずるクラス)&プライベートメソッド&関数を定義しない
プラベーとクラスやプライベートメソッド、関数を利用すると、開発者がその都度「このクラス,プライベートメソッド,関数は何をしているのか？」とスクロールして確認する手間が発生します。
テストコードが「テスト対象コードの仕様書」として上から順に可読できるようにハードコードにしてください。

Bad: プライベートクラスを利用
```python
class _AppServiceTestBase:
    def setup_method(self) -> None:
        self.app_repository = InMemAppRepository()
        self.user_pool_repository = InMemUserPoolRepository()
        self.oauth_client_repository = InMemOAuthClientRepository()
        self.service = AppApplicationService(
            app_repository=self.app_repository,
            user_pool_repository=self.user_pool_repository,
            oauth_client_repository=self.oauth_client_repository,
            base_domain="fastship.jp",
        )

class TestAppApplicationService:
    class Test_provisionメソッドについて(_AppServiceTestBase):
        def test_Appと専属UserPoolと専属OAuthクライアントを作成できる(self) -> None:
            dpo = self.service.provision(
                ProvisionAppCommand(app_id="acme", name="ACME Shop", owner_tenant_id="tenant-1"))
```

Good: ハードコード
```python
class TestAppApplicationService:
    class Test_provisionメソッドについて:
        def setup_method(self) -> None:
            self.app_repository = InMemAppRepository()
            self.user_pool_repository = InMemUserPoolRepository()
            self.oauth_client_repository = InMemOAuthClientRepository()
            self.application_service = AppApplicationService(
                app_repository=self.app_repository,
                user_pool_repository=self.user_pool_repository,
                oauth_client_repository=self.oauth_client_repository,
                base_domain="fastship.jp",
            )

        def test_Appと専属UserPoolと専属OAuthクライアントを作成できる(self) -> None:
            dpo = self.application_service.provision(
                ProvisionAppCommand(app_id="acme", name="ACME Shop", owner_tenant_id="tenant-1"))
```

### ドメインサービスのスタブはテストコードでは定義しない
テストを実施するために必要なドメインサービスのスタブクラスはテストコードに実装するのではなく、プロダクションコードに定義してください。

 - ドメインサービス以外でスタブを利用したい場合は Pytest の Mock を利用すること

Bad: テストコード内にスタブクラスを実装している
```python
# backend/test/unit/app/application/app/test_app_application_service.py
class _StubEntitlement(AppEntitlementService):
    def __init__(self, max_apps: int) -> None:
        self.__max_apps = max_apps

    @override
    def max_apps_of(self, owner_id: OwnerTenantId) -> int:
        return self.__max_apps
```

Good: プロダクションコードに定義
```python
# backend/src/app/port/adapter/service/app/app_entitlement_service_impl.py
class AppEntitlementServiceImpl(AppEntitlementService):
    @inject
    def __init__(self, app_adapter: AppAdapter) -> None:
        self.__app_adapter = app_adapter

    @override
    def max_apps_of(self, owner_id: OwnerTenantId) -> int:
        return self.__app_adapter.max_apps_of(owner_id)

# backend/src/app/port/adapter/service/app/adapter/app_adapter_stub.py
class AppAdapterStub(AppAdapter):
    def __init__(self, max_apps: int) -> None:
        self.__max_apps = max_apps

    @override
    def max_apps_of(self, owner_id: OwnerTenantId) -> int:
        return self.__max_apps
```

例:
 - backend/src/authority/port/adapter/service/app/app_database_service_impl.py
 - backend/src/authority/port/adapter/service/app/adapter/stub.py
 - backend/test/unit/authority/application/identity/test_identity_application_service.py

---
## 🔗 実装例
### ユニットテスト(UT)

**アプリケーション層**:
 - backend/test/unit/app/application/app/test_app_application_service.py
 - backend/test/unit/tenant/application/project/test_project_application_service.py

**ドメイン層**:
 - backend/test/unit/tenant/domain/model/tenant/test_tenant.py
 - backend/test/unit/tenant/domain/model/user/test_user_id.py
 - backend/test/unit/common/domain/model/mail/test_email_address.py

**ポート・アダプター層**:
 - backend/test/unit/authority/port/adapter/persistence/repository/postgresql/user/test_driver_manager_user.py

#### 受け入れテスト

 - backend/test/acceptance/apigateway/test_ヘルスチェックAPI.py
 - backend/test/acceptance/authority/test_ユーザー登録API.py