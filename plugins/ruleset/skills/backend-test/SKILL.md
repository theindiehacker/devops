---
name: backend-test
description: ユニットテストと受入テストの実装方法とルール。テストは仕様書として上から順に読めるように書く。定数を使わずハードコード、テストクラス内のプライベートや継承基底クラスを作らない。ドメインサービスのスタブはプロダクションコードに置く
paths:
  - "backend/test/unit/**/*.py"
  - "backend/test/acceptance/**/*.py"
user-invocable: false
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
            base_domain="example.com",
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
                base_domain="example.com",
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

例: プロダクションコードの `AppAdapterStub`（`ruleset:domain-service` skill の規範例）を `AppDatabaseServiceImpl` に注入し、テストが触らない依存は Pytest の Mock で埋める。

```python
class TestIdentityApplicationService:
    class Test_signup_fieldsメソッドについて:
        def setup_method(self) -> None:
            self.app_adapter_stub = AppAdapterStub()
            self.identity_application_service = IdentityApplicationService(
                oauth_provider_service=Mock(),
                user_repository=Mock(),
                token_repository=Mock(),
                app_database_service=AppDatabaseServiceImpl(self.app_adapter_stub),
                pool_settings_repository=InMemPoolSettingsRepository(),
            )

        def test_App設定の追加入力フィールドを返す(self) -> None:
            self.app_adapter_stub.apps.add(App(
                id=AppId("acme"),
                additional_signup_fields=(TextSignupField("company_name", required=False),),
                front_base_url="https://acme.example.com",
                issuer="https://acme.api.example.com",
            ))

            with CurrentApp.bind_with(AppId("acme"), PoolId.generate()):
                dpo = self.identity_application_service.signup_fields()

            assert dpo.fields == (TextSignupField("company_name", required=False),)

        def test_追加入力フィールドが無いAppでは空を返す(self) -> None:
            self.app_adapter_stub.apps.add(App(
                id=AppId("shop"),
                additional_signup_fields=(),
                front_base_url="https://shop.example.com",
                issuer="https://shop.api.example.com",
            ))

            with CurrentApp.bind_with(AppId("shop"), PoolId.generate()):
                dpo = self.identity_application_service.signup_fields()

            assert dpo.fields == ()
```

---
## 🔗 実装例
### ユニットテスト(UT)

**アプリケーション層**: 上の「ドメインサービスのスタブはテストコードでは定義しない」の例（`TestIdentityApplicationService`）

**ドメイン層**: 値オブジェクトの生成と検証

```python
class TestEmailAddress:
    class Test_生成について:
        def test_妥当なメールアドレスは構築できる(self) -> None:
            assert EmailAddress("test@example.com").text == "test@example.com"

        def test_domainプロパティはアットマーク以降を返す(self) -> None:
            assert EmailAddress("user@example.co.jp").domain == "example.co.jp"

        @pytest.mark.parametrize("value", [None, ""])
        def test_空文字やNoneはValueErrorを送出する(self, value: str | None) -> None:
            with pytest.raises(ValueError, match="must not be empty"):
                EmailAddress(value)  # type: ignore[arg-type]

        def test_長すぎるとValueErrorを送出する(self) -> None:
            with pytest.raises(ValueError, match="must be at most 100 characters"):
                EmailAddress("a" * 95 + "@example.com")  # 107 文字 (上限 100 超過)

        @pytest.mark.parametrize("value", [
            "not-an-email",            # @ がない
            "@example.com",            # local part がない
            "test@",                   # domain がない
            "test@example",            # domain に . がない
            "test@example.com\n",      # 末尾改行
            "test@example.com extra",  # 余剰文字
        ])
        def test_不正な形式はValueErrorを送出する(self, value: str) -> None:
            with pytest.raises(ValueError, match="is invalid"):
                EmailAddress(value)
```

**ポート・アダプター層**: 実 DB に対する DriverManager のテスト（境界キーの強制も仕様として書く）

```python
class TestDriverManagerUser:
    class Test_find_by_tokenメソッドについて:
        def test_トークンは所属Poolを指定したときだけ取得できる(self, unit_of_work: UnitOfWork) -> None:
            token = Token.Type.VERIFICATION.generate()
            user = User(UserId(str(uuid.uuid4())), PoolId.system(),
                        'test1', None, EmailAddress(f'{uuid.uuid4()}@example.com'),
                        None, Tokens(frozenset({token})), False, set(), None)

            driver_manager_user = DIContainer.instance().resolve(DriverManagerUser)

            unit_of_work.start()
            driver_manager_user.insert(user)
            unit_of_work.commit()

            # 所属 Pool と種別を指定すれば取得できる
            assert driver_manager_user.find_by_token(PoolId.system(), Token.Type.VERIFICATION, token.value) == user
            # 別 Pool を指定すると存在しない扱いになる (Pool 境界の強制)
            assert driver_manager_user.find_by_token(PoolId.generate(), Token.Type.VERIFICATION, token.value) is None
            # 別種別を指定すると存在しない扱いになる (種別境界の強制)
            assert driver_manager_user.find_by_token(PoolId.system(), Token.Type.PASSWORD_RESET, token.value) is None
```

#### 受け入れテスト

API を叩き、結果を DB から確かめる。テストデータは uuid で一意にして他テストと衝突させない。

```python
class Test_ユーザー登録API:
    def test_ユーザー名とメールアドレスとパスワード指定でユーザー登録できる(
        self, client: TestClient, unit_of_work: PostgreSQLUnitOfWork
    ) -> None:
        email_address = f'{uuid.uuid4()}@example.com'
        r: Response = client.post('/users/register', json={
            'username': f'user_{uuid.uuid4().hex[:8]}',
            'email_address': email_address,
            'password': 'password'
        })
        assert r.status_code == 200

        # テストは system プレーン (CurrentApp(system)) で動くため system Pool に登録される。
        with unit_of_work.query() as q:
            optional: UsersTableRow | None = q.query(UsersTableRow) \
                .filter_by(pool_id=PoolId.system().value, email_address=email_address) \
                .one_or_none()

        assert optional.email_address == email_address
        assert optional.pool_id == PoolId.system().value
```
