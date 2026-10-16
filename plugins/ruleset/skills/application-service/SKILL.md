---
name: application-service
description: アプリケーション層(アプリケーションサービス)の実装方法。アプリケーションサービスは薄い調整役。プライベートメソッド禁止・1メソッド50行以内。取得は DPO、新規作成/更新は Command で単一集約に対して行う
paths:
  - "backend/src/**/application/**/*.py"
user-invocable: false
---

# アプリケーション層（アプリケーションサービス）とは
「アプリケーションサービス」とはアプリケーション層に存在するドメインモデルのクライアントとなります。
アプリケーションサービスはあくまでドメイン層とUI層(ポート・アダプター層, プレゼンテーション層)との調整役であるため、薄い処理を行うだけのレイヤーとなります。

- アプリケーションサービスの責務は、タスクの調整であり、ユースケースのイベントフローごとにメソッドを提供します。
- アプリケーションサービスは、データベースのトランザクション管理を行います

# ドメイン層とUI層における情報の受け渡し方法
UI層で描画するデータを取得するためには「複数の集約」の情報を組み合わせる必要があります。
逆に新規作成/更新操作を行う場合にはUI層で入力された値を「1つの集約」に対して新規作成/更新依頼することが一般的です。

 - 取得処理: 集約をUI層にそのまま返さずに DPO (Data Payload Object) に複数の集約インスタンスを詰めて、UI層に表示します
   - DPOの実装方法: `ruleset:dpo` skill
 - 新規作成/更新処理: コマンド(更新の指示情報をまとめた入れ物)を指定して、単一の集約を新規作成/更新します

```python
class 〇〇ApplicationService:
    def get(self, id: str) -> 〇〇Dpo:
        """取得系"""
        # 複数の集約のインスタンスを DPO に詰めて返却します
        ...
    
    @transactional
    def save(self, command: 〇〇Command) -> None:
        """"新規作成/更新系"""
        # 新規作成/更新操作を行う場合はコマンドに詰めて渡し、1つの集約に対して保存します
        ...
```

# フォルダ構成

```
backend/src/**/application/**
├── __init__.py
├── 〇〇_application_service.py  # アプリケーションサービス
├── command.py                  # コマンド
└── dpo.py                      # DPO
```

# 実装
## 禁止事項
下記 2 つに触れたら、ロジックの引き上げ先の判断基準として `ruleset:domain-model` skill（ドメイン貧血症）と `ruleset:aggregate` skill（不変条件は集約メソッドで守る）を参照する。

 - プライベートメソッド&関数は実装する: アプリケーションサービスでプライベートメソッドおよび関数を実装する/したいケースは、大抵ドメイン層配下のドメインオブジェクトのメソッドとして定義すべきドメインロジックがアプリケーションサービスに漏れている時である。
 - メソッドが50行よりも長くなる: 収められないケースは「ドメインオブジェクトのメソッド化が漏れている」「必要なドメインオブジェクトが欠落している」ときである。ドメイン層の実装を見直してください。 

## メソッド

 - 新規作成/更新系は特別な理由がない限り**1つの `save` メソッド**を提供するように実装してください。
   - こうすることで、集約の作成/更新項目が増えたり減ったりしてもこの `save` メソッド内のみ変更すれば良いので、メンテナンスしやすくなります

## 参考

**アプリケーションサービス**

`IdentityApplicationService`（抜粋）: 更新系は `@transactional` を付け、Command を受けて単一の集約（`User`）を作成/更新し、リポジトリに保存する。業務ルールは集約メソッド（`User.provision` / `request_email_verification` / `protect_password`）に任せ、サービスは呼び出し順の調整だけを行う。

```python
@singleton
class IdentityApplicationService:
    @inject
    def __init__(self,
                 oauth_provider_service: OAuthProviderService,
                 user_repository: UserRepository,
                 token_repository: TokenRepository,
                 app_database_service: AppDatabaseService,
                 pool_settings_repository: PoolSettingsRepository):
        self.oauth_provider_service = oauth_provider_service
        self.user_repository = user_repository
        self.token_repository = token_repository
        self.app_database_service = app_database_service
        self.pool_settings_repository = pool_settings_repository

    @transactional
    def register(self, command: RegisterUserCommand) -> UserDpo:
        """ユーザー登録

        メアド検証メールの送信は VerificationTokenGenerated イベントを購読する notify モジュールが行う。
        """
        # pool_id は Command ではなくリクエスト文脈 (CurrentApp) から取得する
        pool_id = CurrentApp.get().pool_id
        self.pool_settings_repository.settings_of(pool_id).validate_password(command.user.plain_password)
        email = EmailAddress(command.user.email_address)
        user = self.user_repository.user_with_email_address(pool_id, email)
        if user and user.is_verified():
            # すでに本登録が完了している場合は例外を送出
            raise SystemException(
                ErrorCode.REGISTER_USER_ALREADY_EXISTS,
                f"メールアドレス {user.email_address.text} がすでに登録されています。",
            )

        if user:
            # 仮登録中のユーザーの場合は、再度メアド検証用のトークンを発行する。
            user.request_email_verification()
            user.protect_password(command.user.plain_password)
        else:
            # ユーザーを新規作成。company_name は account を飛ばすためキーワードで渡す。
            user = User.provision(
                self.user_repository.next_identity(),
                pool_id,
                command.user.username,
                email,
                command.user.plain_password,
                company_name=command.company_name,
            )

        self.user_repository.add(user)
        return UserDpo(user)

    @transactional
    def resend_email_verification(self, command: ResendEmailVerificationCommand) -> None:
        """メールアドレス認証メールを再送信する"""
        email = EmailAddress(command.email_address)
        user = self.user_repository.user_with_email_address(CurrentApp.get().pool_id, email)
        if user is None or user.is_verified():
            # 悪意のあるユーザーに対して余計や情報を与えないために、例外を送出しない
            return

        # 仮登録中のユーザーの場合は、メアド検証用のトークンを発行する
        user.request_email_verification()
        self.user_repository.add(user)

    ...
```

`AuthenticationApplicationService`: ドメインサービス（`IdentityAccessService`）で認証し、結果を DPO に詰めて返すだけの薄い取得系。

```python
@singleton
class AuthenticationApplicationService:
    @inject
    def __init__(self,
                 identity_access_service: IdentityAccessService,
                 secret_manager_service: SecretManagerService):
        self.identity_access_service = identity_access_service
        self.secret_manager_service = secret_manager_service

    def publish_internal_token(self, access_token_value: str) -> InternalTokenDpo:
        user = self.identity_access_service.authenticate(access_token_value)

        if user is None:
            # detail は e.logging() でログに出るため、資格情報である生トークン値は先頭 8 文字のみ残す
            raise SystemException(ErrorCode.INVALID_TOKEN, f"アクセストークン {access_token_value[:8]}... は無効です。")

        private_key = self.secret_manager_service.get(Key.JWT_PRIVATE)
        return InternalTokenDpo(UserToken.generate(user), private_key)
```

**コマンド**

Command はプリミティブだけを持つ不変の入れ物。値オブジェクトへの変換はアプリケーションサービス（または集約）で行う。入れ子の構造は内部クラスで表す。

```python
@dataclass(init=True, unsafe_hash=True, frozen=True)
class RegisterUserCommand:
    @dataclass(init=True, unsafe_hash=True, frozen=True)
    class User:
        username: str
        email_address: str
        plain_password: str

    user: User
    company_name: str | None = None


@dataclass(init=True, unsafe_hash=True, frozen=True)
class ResetPasswordCommand:
    reset_token: str
    password: str
```
