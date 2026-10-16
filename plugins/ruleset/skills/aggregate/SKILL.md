---
name: aggregate
description: 集約・エンティティの設計/実装方法。集約は1トランザクション=1整合性境界。他集約は ID 値オブジェクトで参照し内包しない。不変条件は集約メソッドで守り生成は静的ファクトリ。1Tx で複数集約を更新しない
paths:
  - "backend/src/**/domain/model/**/*.py"
user-invocable: false
---
# 集約 (Aggregate) / エンティティ

集約は **1 トランザクション = 1 整合性境界**。「同時に必ず整合していなければならないオブジェクトの塊」を 1 つの集約にまとめ、集約ルート経由でのみ操作する。

規範例は末尾の「規範例」節（`User` 集約 / `Tenant` 集約）。迷ったらこれを写す。

## 境界の切り方（判断ヒューリスティック）

 - **不変条件で切る**: 「この 2 つは常に同時に正しくないと壊れる」なら同じ集約。「結果整合で良い」なら別集約 + イベント連携。
 - **1 集約 = 1 リポジトリ = 1 トランザクション**。1 ユースケースで複数集約を更新したくなったら、境界が間違っているか、**プレーン/集約を跨ぐ副作用をドメインイベントにすべき**サイン（`ruleset:domain-event` skill）。
 - **集約は小さく保つ**。「参照したいから」で内包しない。参照は下記の ID 値オブジェクトで持つ。
 - 迷ったら「トランザクション境界はどこか」を先に決める。それが集約境界。

## 他集約は "ID 値オブジェクト" で参照する（オブジェクトを内包しない）

 - 他集約のインスタンスをフィールドに持たない。**ID 値オブジェクト（`UserId` / `AppId` / `PoolId` 等）で参照**する。
 - 別モジュールの集約が必要なときは import せず、ACL（腐敗防止層）越しに読む（`ruleset:domain-service` skill、実例 `AuthorityAdapter`）。
 - import-linter がモジュール跨ぎの内部 import を機械的に禁止しているので、構造違反は `task style:check` で落ちる。

## 実装規約

 - `@dataclass(init=True, eq=False)` とし、**同一性は ID で判定**する（`__eq__` / `__hash__` を `id` ベースで実装）。値等価にしない。
 - **生成は静的ファクトリメソッド**（例: `User.provision(...)` / `Tenant.provision(...)`）。`__init__` を業務語彙にせず、ファクトリ名にユビキタス言語の動詞を使う。
 - **不変条件は集約メソッド内で守る**。「リセットは PASSWORD_RESET トークンのみ」「最後の連携は解除不可」のように、壊れた状態を作らせないガードをメソッドに書く（規範例 `User.reset_password` / `User.unlink`、`Tenant.invite` / `Tenant.accept`）。リポジトリ側のスコープと二重になっても、集約単体を最終防衛線にする。
 - **状態変化はドメインイベントを publish** する: `DomainEventPublisher.instance().publish(...)`（規範例 `User.provision` / `User.request_email_verification`、`Tenant.invite`）。プレーンを跨ぐ副作用はイベントに寄せる。
 - **ドメインサービスが要るロジックは集約内から `DomainRegistry.resolve(IF)`** で解決する（例: `User.protect_password` が `EncryptionService` を解決）。application 層に IF を渡させない。

## アンチパターン（レビューで弾く / `anemic-domain-model` の芽）

 - ❌ ゲッター/セッターとプロパティだけで**振る舞いメソッドが無い**集約（= ドメイン貧血症）。ユビキタス言語の動詞は集約メソッドになる（`ruleset:domain-model` skill）。
 - ❌ アプリケーションサービスが集約のフィールドを直接書き換えて不変条件を組み立てている（ロジック漏れ）。その手続きは集約メソッドに引き上げる。
 - ❌ 他集約インスタンスを内包している（ID 参照にする）。
 - ❌ 1 トランザクションで複数集約を更新している（境界の誤り or イベント化漏れ）。

## 規範例

### User 集約（抜粋）

```python
@dataclass(init=True, eq=False)
class User:
    id: UserId
    pool_id: PoolId  # 所属 User Pool も ID 値オブジェクトで参照する
    username: str
    image: URL | None
    email_address: EmailAddress
    encrypted_password: str | None
    tokens: Tokens
    enable: bool
    accounts: set[Account]
    verified_at: datetime | None

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, User):
            return False
        return self.id == other.id

    def __hash__(self) -> int:
        return hash(self.id)

    @staticmethod
    def provision(user_id: UserId,
                  pool_id: PoolId,
                  username: str,
                  email_address: EmailAddress,
                  plain_password: str | None = None,
                  account: Account | None = None,
                  company_name: str | None = None) -> User:
        """ユーザーを作成する。pool_id は所属 User Pool (一意性 (pool_id, email) の境界)。

        company_name は provisioning 時の文脈 (契約企業名) を UserProvisioned に中継するためだけの引数で、
        User 集約の状態にはしない (会社名の着地先は tenant.Tenant であり、authority は tenant 語彙を持たない)。
        """
        enable = False
        accounts = set()
        verified_at = None
        if account:
            # GitHub や Google で登録した場合、account が存在します。この場合、メアド認証は不要になるので enable を True にします。
            enable = True
            accounts.add(account)
            verified_at = datetime.now().astimezone(pytz.timezone("Asia/Tokyo"))

        user = User(user_id, pool_id, username, None, email_address, None, Tokens(), enable, accounts, verified_at)

        if plain_password:
            user.protect_password(plain_password)

        if enable is False:
            # メアド検証用のトークンを発行する
            user.request_email_verification()

        DomainEventPublisher\
            .instance()\
            .publish(UserProvisioned(user.id, user.pool_id, company_name))
        return user

    def protect_password(self, plain_password: str) -> None:
        """平文パスワードを暗号化して、保存できる"""
        self.encrypted_password = DomainRegistry.resolve(EncryptionService).encrypt(plain_password)  # type: ignore[type-abstract]

    def reset_password(self, new_plain_password: str, reset_token: str) -> None:
        """新しく設定したパスワードとパスワードリセットトークン指定で新しいパスワードに変更する"""
        token = self.tokens.with_value(reset_token)
        if token is None or not token.is_(Token.Type.PASSWORD_RESET):
            # Repository 側の種別スコープと二重になるが、集約単体でも「リセットは PASSWORD_RESET
            # トークンのみ」という不変条件を保つ (別経路からの呼び出しに対する最終防衛線)。
            raise ValueError("パスワードのリセットトークンが不正です。")

        self.protect_password(new_plain_password)
        self.tokens = self.tokens.without(Token.Type.PASSWORD_RESET)

    def request_email_verification(self) -> Token:
        """メール検証を要求する。有効な検証トークンがあれば再利用し、無ければ発行する。"""
        self.tokens, token = self.tokens.generate(Token.Type.VERIFICATION)
        DomainEventPublisher\
            .instance()\
            .publish(VerificationTokenGenerated(self.id, self.email_address, token))
        return token

    def verified(self) -> None:
        """ユーザー確認を完了できる"""
        self.enable = True
        self.verified_at = datetime.now().astimezone(pytz.timezone("Asia/Tokyo"))
        self.tokens = self.tokens.without(Token.Type.VERIFICATION)

    def unlink(self, provider: Account.Provider) -> None:
        accounts = set({a for a in self.accounts if a.provider != provider})
        if len(accounts) == 1 and self.encrypted_password is None:
            raise ValueError(f"{provider.name} の連携を解除できません。")
        self.accounts = accounts

    ...
```

### Tenant 集約（抜粋）

```python
@dataclass(init=True, eq=False)
class Tenant:
    id: TenantId
    name: str
    app_id: AppId
    invitations: set[Invitation]
    members: Members

    def __hash__(self) -> int:
        return hash(self.id.value)

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Tenant):
            return False
        return self.id == other.id

    @staticmethod
    def provision(tenant_id: TenantId, name: str, app_id: AppId) -> Tenant:
        return Tenant(tenant_id, name, app_id, set(), Members())

    def invite(self, email_address: EmailAddress, role: Member.Role) -> Invitation:
        """メールアドレスとロール指定でメンバーを招待する。

        同一メール宛の有効な招待は最大 1 通 (再呼び出し = 再送)。既存の招待 (期限切れ含む) を
        破棄して新しい招待に差し替えるため、同じ宛先へ複数の有効な招待が並存しない。
        """
        # 招待経由では OWNER を付与しない (EDITOR も招待でき、招待での OWNER 付与は権限昇格になる)。
        # OWNER への昇格は OWNER のみ実行できる change_member_role 経由に限定する多層防御。
        if role is Member.Role.OWNER:
            raise ValueError("OWNER ロールは招待では付与できません")

        # 再送 = 取り消し + 発行: 同一メール宛の既存招待を破棄してから新規発行する (宛先ごとに有効な招待は 1 通)。
        self.withdraw_invitations(email_address)
        invitation = Invitation.generate(email_address, role)
        self.invitations.add(invitation)

        # メンバー招待ドメインイベントを発行 (招待メールは notify が購読して送信)
        DomainEventPublisher.instance().publish(MemberInvited(
            tenant_id=self.id.value, email_address=invitation.to, code=invitation.code, tenant_name=self.name,
        ))

        return invitation

    def withdraw_invitations(self, email_address: EmailAddress) -> None:
        """指定メールアドレス宛の招待をすべて破棄する (取り消し。該当が無くても冪等)"""
        self.invitations = {inv for inv in self.invitations if inv.to != email_address}

    def accept(self, user_id: UserId, code: str) -> None:
        """招待を受け入れてメンバーとして参加する"""
        # 該当する招待コードを検索
        invitation = next((inv for inv in self.invitations if inv.code == code), None)
        if invitation is None:
            raise ValueError("該当する招待コードが見つかりません")

        # 招待が有効か確認
        if not invitation.is_available():
            raise ValueError("招待が期限切れです")

        # 既にメンバーでないか確認
        if self.has_member(user_id):
            raise ValueError("既にメンバーです")

        # メンバーとして追加
        new_member = Member(user_id, invitation.role)
        self.members.add(new_member)

        # 参加が確定したら、その宛先への招待を取り消す (受諾済みコードを無効化)
        self.withdraw_invitations(invitation.to)

    def has_member(self, user_id: UserId, role: Member.Role = None) -> bool:
        """該当ユーザーがテナントに属しているか判定できる"""
        return self.members.has(user_id, role)

    ...
```
