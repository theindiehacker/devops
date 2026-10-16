---
name: domain-service
description: ドメインサービスの設計/実装方法（使いどころ + ファクトリとしての ACL / 腐敗防止層）。ドメインサービスは最終手段。別コンテキストの概念は ACL(自コンテキストのセパレート IF＋翻訳アダプタ)越しに自前 read-model へ翻訳して読み、相手集約を import しない
paths:
  - "backend/src/**/domain/model/**/*.py"
  - "backend/src/**/port/adapter/service/**/*.py"
user-invocable: false
---
# ドメインサービス (Domain Service)

ドメインサービスとは、あるロジックを実現したいがエンティティ/値オブジェクト/集約/コンポジションに実装するのが不適切である場合に用いるものです。

 - 大抵のロジックは、エンティティ/値オブジェクト/集約/コンポジションのプロパティやメソッドとして実装できるので、ドメインサービスはなくても問題ありません
 - ドメインサービスを多用すると、次のような問題が発生します
   - プロパティだけのエンティティ/値オブジェクトが発生(ドメイン貧血症。`ruleset:domain-model` skill)
   - ドメインサービスにロジックが集中し、バグの温床になる/テストコードが肥大化する
 - たとえば、「複数のエンティティ/値オブジェクト/集約/コンポジションをもとに計算するロジック」など、どうしてもエンティティや値オブジェクトなどで実装できない時や不適切である時にだけドメインサービスを導入しましょう

## ファクトリとしてのドメインサービス（境界付けられたコンテキストからドメインオブジェクトを取得するドメインサービス）

別の境界付けられたコンテキストが持つ概念を自コンテキストで使いたいとき、相手の集約やリポジトリを直接触らない。
**「相手コンテキストからドメインオブジェクトを取り出す」責務を、自コンテキストのドメインサービス（＝ファクトリ）として表す**。
これはリポジトリ（自集約の永続化。1 集約ルート = 1 リポジトリ。`ruleset:repository` skill）ではない ―― 返すのは相手の集約ではなく、翻訳済みの**自コンテキストの read-model** だからだ。

 - **セパレートインターフェースによるドメインサービス**: 「相手の情報が要る」という*要求*はドメインの語彙なので、IF（`abc.ABC`）は自コンテキストの **domain 層**に置く（例 `UserDatabaseService` / `AppDatabaseService`）。「どう取ってくるか」（相手の公開 Resource を叩く）はインフラの都合なので実装は **port/adapter 層**へ分離する（＝セパレートインターフェース）。domain 層は相手モジュールを import せず、IF と自前 read-model だけを見る。
 - **腐敗防止層 = アダプター + トランスレーター**: 実装側は、相手コンテキストの語彙が自コンテキストに漏れ込むのを防ぐ ACL になる。
   - **アダプター**: 相手の**公開 Resource**（`AppResource` 等）を呼び、型付き応答（`AppJson` / `UserJson` 等）を受け取る。相手の内部集約ではなく公開 IF だけに依存する。
   - **トランスレーター**: その型付き応答を**自コンテキストの read-model 値オブジェクトへ写像**し、相手の語彙を自分の意図に翻訳する（例: `app` の `mode="b2b"` → `tenant` の「新規登録で契約企業を作るか」）。**同じ App 概念でもコンテキストごとに read-model が違う**のが要諦。
 - 返す read-model は相手の集約とは**別物の「自コンテキストのユビキタス言語にある値オブジェクト」**。

規範例（コードは末尾の「規範例」節）:
 - App 設定読み取り（authority）: `AppDatabaseService`（IF）→ `AppDatabaseServiceImpl` → `AppAdapter`（`mode` を追加入力フィールドへ翻訳）。同型が `tenant` / `apigateway` にもある。
 - User 読み取り（tenant）: `UserDatabaseService`（IF）→ `AuthorityAdapter` + `AuthorityTranslator`。
 - トークン認証（apigateway）: `IdentityAccessService`（IF）→ `AuthorityAdapter`。**命名は `_database_service` に限らない**（サービス名はユビキタス言語で付ける。dir は `user` だがサービス名は `identity_access`）。

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
※ `stub.py`（テスト用スタブ）は**テストコードでなくプロダクションコードに置く**（`ruleset:backend-test` skill の「ドメインサービスのスタブはテストコードでは定義しない」）。

## 規範例

### App 設定読み取り（authority コンテキスト。4 点セット一式）

```python
# domain/model/app/app_database_service.py ― セパレート IF（ドメイン層）
class AppDatabaseService(abc.ABC):
    @abc.abstractmethod
    def app_of(self, app_id: AppId) -> App:
        """app_id から App コンテキストの App 情報を取得する。

        未知の App は SystemException (COMMON_2004) を送出する (None は返さない)。
        """


# domain/model/app/app.py ― 自前 read-model（相手の App 集約とは別物）
@dataclass(frozen=True)
class App:
    """authority コンテキストが参照する App 情報 (App コンテキストからの腐敗防止層で翻訳した値)。

    App コンテキストの mode (B2C/B2B) 等の語彙は adapter の翻訳境界に閉じ込め、authority 側は
    「signup で追加入力させるフィールド」という自コンテキストの意図だけを保持する。
    """
    id: AppId
    additional_signup_fields: tuple[SignupField, ...]
    front_base_url: str
    issuer: str


# port/adapter/service/app/app_database_service_impl.py ― Service 実装（adapter に委譲するだけ）
class AppDatabaseServiceImpl(AppDatabaseService):
    @inject
    def __init__(self, app_database_adapter: AppDatabaseAdapter):
        self.__app_database_adapter = app_database_adapter

    @override
    def app_of(self, app_id: AppId) -> App:
        """app_id から App コンテキストの App 情報を取得する。"""
        return self.__app_database_adapter.app_of(app_id)


# port/adapter/service/app/adapter/app_database_adapter.py ― 二次抽象（DI 差し替え口）
class AppDatabaseAdapter(abc.ABC):
    @abc.abstractmethod
    def app_of(self, app_id: AppId) -> App:
        """app_id から App コンテキストの App 情報を取得する。"""


# port/adapter/service/app/adapter/app.py ― 翻訳アダプタ（アダプター + トランスレーター）
class AppAdapter(AppDatabaseAdapter):
    """App コンテキストの公開 Resource (AppResource) 経由で App 情報を取得するアダプター。"""

    def __init__(self) -> None:
        self.__app_resource = AppResource()

    @override
    def app_of(self, app_id: AppId) -> App:
        # AppResource の型付き応答 (AppJson) を消費し、App コンテキストの語彙を authority の意図に翻訳する:
        #   - mode -> 追加入力フィールド (b2b -> 会社名 (任意) / b2c -> フィールドなし)
        #   - front_base_url / issuer は素通し (発行者の正は app 集約。authority は再導出しない)
        response: AppJson = self.__app_resource.from_slug(app_id.slug)
        fields = (TextSignupField("company_name", required=False),) if response.mode == "b2b" else ()
        return App(
            id=AppId.of(response.id),
            additional_signup_fields=fields,
            front_base_url=response.front_base_url,
            issuer=response.issuer,
        )


# port/adapter/service/app/adapter/stub.py ― テスト用スタブ（プロダクションコードに置く）
class AppAdapterStub(AppDatabaseAdapter):
    def __init__(self) -> None:
        self.apps: set[App] = set()

    @override
    def app_of(self, app_id: AppId) -> App:
        for app in self.apps:
            if app.id == app_id:
                return app
        raise ValueError(f"{app_id} is not a registered app")
```

### User 読み取り（tenant コンテキスト）

tenant は authority の `User` 集約を import せず、自分が要る項目だけを持つ read-model に翻訳する。

```python
# domain/model/user/user_database_service.py ― セパレート IF
class UserDatabaseService(abc.ABC):
    @abc.abstractmethod
    def users_of(self, user_ids: set[UserId]) -> set[User]:
        """ユーザーID指定でユーザー情報を取得する"""


# domain/model/user/user.py ― 自前 read-model
@dataclass(init=True, unsafe_hash=True, frozen=True)
class User:
    id: UserId
    username: str
    email_address: EmailAddress


# port/adapter/service/user/adapter/authority.py ― アダプター + トランスレーター
class AuthorityAdapter(UserDatabaseAdapter):
    def __init__(self) -> None:
        self.__translator = AuthorityTranslator()
        self.__user_resource = UserResource()

    @override
    def users_of(self, user_ids: set[UserId]) -> set[User]:
        """ユーザーID指定でユーザー情報を取得する"""
        if not user_ids:
            return set()

        response = self.__user_resource.get_users(user_ids={user_id.value for user_id in user_ids})
        return self.__translator.from_(response)


class AuthorityTranslator:
    @staticmethod
    def from_(response: list[UserJson]) -> set[User]:
        users = set()
        for user_json in response:
            user = User(
                id=UserId(user_json.id),
                username=user_json.username,
                email_address=EmailAddress(user_json.email_address),
            )
            users.add(user)
        return users
```

### トークン認証（apigateway コンテキスト）

サービス名はユビキタス言語で付ける（dir は `user`、サービス名は `identity_access`）。アダプターは相手の例外も自コンテキストのエラーコードへ翻訳する。

```python
# domain/model/user/identity_access_service.py ― セパレート IF
class IdentityAccessService(abc.ABC):
    @abc.abstractmethod
    def authenticate(self, access_token: str) -> User:
        pass


# port/adapter/service/user/adapter/authority.py ― アダプター（抜粋）
class AuthorityAdapter(IdentityAccessAdapter):
    @override
    def authenticate(self, access_token: str) -> User:
        try:
            user_dpo = self.__auth_resource.authorization_application_service.identify(access_token)
        except SystemException as e:
            # 越境利用のみ apigateway のエラーコードへ翻訳する (腐敗防止層)
            if e.error_code is AuthorityErrorCode.TOKEN_AUDIENCE_MISMATCH:
                raise SystemException(ErrorCode.TOKEN_AUDIENCE_MISMATCH, e.detail) from e
            raise
        memberships = self.__tenant_resource.tenants_of(user_dpo.user.id.value)
        return User(
            id=UserId(user_dpo.user.id.value),
            username=user_dpo.user.username,
            email_address=EmailAddress(user_dpo.user.email_address.text),
            ...
        )
```
