---
name: domain-event
description: ドメインイベントの設計/実装方法。集約/プレーンを跨ぐ副作用はドメインイベントで伝播する。過去形で命名し to_dict はプリミティブのみ。発行は集約メソッド内で行い application 層から publish しない
paths:
  - "backend/src/**/domain/model/**/*.py"
user-invocable: false
---
# ドメインイベント (Domain Event)

**集約/プレーンを跨ぐ副作用はドメインイベントで伝播する**（1 トランザクションに閉じ込めない）。「起きた事実」を過去形で表す。

基底クラスと規範例は末尾の「基底・規範例」節（基底 `DomainEvent` / `DomainEventPublisher` / `DomainEventSubscriber` / `ProcessingPlane`、イベント実装 `UserProvisioned` / `VerificationTokenGenerated`、別モジュールの購読側 `VerificationTokenGeneratedListener`）。

## いつイベントにするか

 - **プレーンを跨ぐ副作用**（Control ↔ App、例: App 作成 → App プレーンへのスコープ provision）は必ずイベント。単一トランザクションにしない（1 リクエスト = 1 app_id = 1 プレーン = 1 DB に閉じる。プレーンをまたぐ副作用はドメインイベント (Pub/Sub) で伝播する）。
 - **別集約/別モジュールへの波及**（ユーザー登録 → 検証メール送信 = notify モジュール）はイベント。呼び出し側は購読側を知らない。
 - **横断集計**（手数料・売上のような別プレーンへの射影）はイベントで射影を作る。App DB を横断クエリしない。
 - 逆に、同一集約内で閉じる整合はイベントにしない（メソッドで同期的に守る）。

## 実装規約

 - **過去形で命名**する（`UserProvisioned` / `VerificationTokenGenerated` / `MemberInvited`）。命令形にしない。
 - `DomainEvent` を継承し、`__init__` で `super().__init__(event_version, occurred_on)` → `super().__setattr__(...)` で属性設定（frozen なため）。
 - **`to_dict()` はプリミティブのみ**返す（MQ ペイロード）。ID 値オブジェクトは `.value` に落とす（規範例 `UserProvisioned.to_dict` / `VerificationTokenGenerated.to_dict`）。集約インスタンスを載せない。
 - **発行は集約メソッド内**から `DomainEventPublisher.instance().publish(...)`（application 層から publish しない。状態変化の事実と発行を同じ場所に置く）。
 - **発生元と別プレーンで処理させたい場合のみ** `processing_plane()` を override して `ProcessingPlane(app_id, pool_id)` を返す（既定 `None` = 発生元プレーンで処理）。override すると全購読者が申告先で処理される点に注意（詳細は基底 `DomainEvent.processing_plane` の docstring）。
 - 購読は `port/adapter/messaging/*_listener.py` に置く（ドメイン層に購読側を書かない）。

## アンチパターン

 - ❌ プレーン/集約跨ぎの更新を 1 トランザクションで同期実行（イベント化漏れ）。
 - ❌ `to_dict()` に VO やエンティティをそのまま入れる（プリミティブに落とす）。
 - ❌ application サービスからイベントを publish する（集約メソッドに寄せる）。
 - ❌ 現在形・命令形のイベント名（`CreateUser` 等）。

## 基底・規範例

### 基底クラス（抜粋）

```python
@dataclass(frozen=True)
class ProcessingPlane:
    """イベントを処理すべきプレーン (処理先 App) の自己申告値。

    通常イベントは発生元プレーン (発行時の CurrentApp) で処理されるが、プレーンをまたぐ副作用を
    起こすイベント (例: Control プレーンの App 作成 → App プレーンへのスコープ provision) は、
    処理先の App を自己申告することで subscriber を処理先プレーンに bind させる。
    CurrentApp (common.application) を戻り値にすると domain 層から application 層への依存に
    なるため、AppId / PoolId のみの値オブジェクトとして domain 層に置く。
    """
    app_id: AppId
    pool_id: PoolId


@dataclass(init=True, unsafe_hash=True, frozen=True)
class DomainEvent(abc.ABC):
    """ドメインイベント"""
    event_version: int
    occurred_on: datetime = field(default_factory=lambda : datetime.now(pytz.timezone("Asia/Tokyo")))

    def __post_init__(self) -> None:
        if self.event_version is None or self.event_version < 0:
            raise ValueError("event_version must be >= 0")
        if self.occurred_on is None or not isinstance(self.occurred_on,  datetime):
            raise ValueError("occurred_on must be set")

    @property
    def type(self) -> str:
        return f"{self.__class__.__name__}.{self.event_version}"

    @abc.abstractmethod
    def to_dict(self) -> dict:
        """MQのペイロードとして送信するJSON形式の値を指定"""

    def processing_plane(self) -> ProcessingPlane | None:
        """イベントを処理すべきプレーンの自己申告。既定 (None) は発生元 (発行時の CurrentApp)。

        subscriber は envelope の app_payload が指すプレーンに bind して「consumed marker +
        副作用 + commit」を単一トランザクションで処理するため、発生元と異なるプレーンで処理
        させたいイベントだけが override する。申告すると全購読者が申告先プレーンで処理される
        点に注意 (発生元プレーンでの副作用も必要になったら、別イベントに分けること)。
        """
        return None


class DomainEventPublisher(threading.local):
    """スレッドローカルなドメインイベントパブリッシャー (instance() でシングルトンを取得する)"""

    ...

    def publish(self, domain_event: DomainEvent) -> None:
        for subscriber in self.__subscribers:
            # サブスクライブするクラスタイプを取得し、型をチェックする
            if isinstance(domain_event, subscriber.subscribed_to_event_type()):
                subscriber.handle_event(domain_event)

    def subscribe(self, subscriber: DomainEventSubscriber) -> None:
        self.__subscribers.add(subscriber)


class DomainEventSubscriber[T](abc.ABC):
    """サブスクライバー"""

    @abc.abstractmethod
    def handle_event(self, domain_event: T) -> None:
        pass

    @abc.abstractmethod
    def subscribed_to_event_type(self) -> type[T]:
        pass
```

### イベント実装

```python
class UserProvisioned(DomainEvent):
    user_id: UserId
    pool_id: PoolId
    company_name: str | None

    def __init__(self, user_id: UserId, pool_id: PoolId, company_name: str | None = None):
        super().__init__(1, datetime.datetime.now().astimezone(pytz.timezone("Asia/Tokyo")))
        super().__setattr__("user_id", user_id)
        super().__setattr__("pool_id", pool_id)
        super().__setattr__("company_name", company_name)

    def to_dict(self) -> dict:
        # ID 値オブジェクトのみ .value に落とす。company_name は素の str なのでそのまま載せる。
        return {"user_id": self.user_id.value, "pool_id": self.pool_id.value, "company_name": self.company_name}


class VerificationTokenGenerated(DomainEvent):
    user_id: UserId
    email_address: EmailAddress
    token: Token

    def __init__(self, user_id: UserId, email_address: EmailAddress, token: Token,
                 occurred_on: datetime.datetime | None = None):
        super().__init__(1, occurred_on or datetime.datetime.now().astimezone(pytz.timezone("Asia/Tokyo")))
        super().__setattr__("user_id", user_id)
        super().__setattr__("email_address", email_address)
        super().__setattr__("token", token)

    @override
    def to_dict(self) -> dict:
        return {"user_id": self.user_id.value, "email_address": self.email_address.text, "token": self.token.value}
```

発行は集約メソッドから行う（`ruleset:aggregate` skill の `User.provision` / `User.request_email_verification`）。

### 購読側（別モジュール。notify の `port/adapter/messaging/`）

ペイロードは `to_dict()` の形の JSON で届くので、購読側は `TypedDict` で受け、発行元の集約を import しない。

```python
class VerificationTokenGenerated(TypedDict):
    user_id: str
    email_address: str
    token: str


@set_logger
class VerificationTokenGeneratedListener(ExchangeListener):
    """authority のメアド認証トークン発行イベントを購読し、認証メールを送信する。"""

    ...

    @override
    async def filtered_dispatch(self, event_type: str, text_message: str) -> None:
        payload: NotificationJson[VerificationTokenGenerated] = json.loads(text_message)
        event = payload["event"]
        # 解決失敗は例外を伝播させ nack → 再配送する (フォールバックしない)
        app_id = CurrentApp.get().app_id
        front_base_url = (AppSettings.instance().frontend_url if app_id.is_system
                          else self.app_database_service.app_of(app_id).front_base_url)
        self.service.send(SendEmailCommand(
            to=event["email_address"],
            template_key="verification",
            variables={"verify_url": f"{front_base_url}/auth/new-verification?token={event['token']}"},
            idempotency_key=f"evt:{payload['notification_id']}",
        ))

    @override
    def publisher_name(self) -> str:
        return "authority"

    @override
    def listens_to(self, event_type: str) -> bool:
        return event_type == "VerificationTokenGenerated.1"
```
