---
name: value-object
description: 値オブジェクト (Value Object) の設計/実装方法。業務概念を生 str/int で引き回さず VO 化する(primitive obsession 撲滅)。VO は不変・値等価・自己検証で不正値は生成不可。取り違えると事故る ID は別々の VO
paths:
  - "backend/src/**/domain/model/**/*.py"
user-invocable: false
---
# 値オブジェクト (Value Object)

「概念に名前と制約と振る舞いを与える」ための不変オブジェクト。**primitive obsession（`str` / `int` の生値を業務概念のまま引き回すこと）を撲滅する**のが目的。

規範例（コードは末尾の「規範例」節）:
 - 単純: `EmailAddress`
 - ポリモーフィック（形式で分岐）: `ClientId` → `URLClientId` / `RegisteredClientId`
 - 共有 VO は `common/domain/model/` 配下（`AppId` / `PoolId` / `EmailAddress` / `URL` / `Amount` 等）。**複数モジュールで共有する ID・業務概念だけ common に置く**（業務語彙を common に溜めない）。

## VO にすべきかの判断

 - その値に**バリデーション/制約がある**（メール形式、長さ上限、slug 予約語）→ VO。
 - その値に**振る舞いがある**（`EmailAddress.domain` でドメイン部を返す等）→ VO。
 - **取り違えると事故る ID**（`user_id` と `pool_id` を混同したくない）→ 別々の VO。生 `str` で引き回さない。
 - 単なる表示用の一次データで制約も振る舞いも無い → プリミティブのままで良い（VO 化の過剰も禁物）。

## 実装規約

 - **不変**にする: `@dataclass(..., frozen=True)`。値等価（`eq=True` / `unsafe_hash=True`）。
 - **自己検証**: 不正な値では**生成できない**ようにする。`__init__(init=False)` + `super().__setattr__(...)`（`EmailAddress`）か、`__post_init__` でバリデーション（`ClientId` サブクラス）。生成に成功した VO は常に正しい、という不変条件を保証する。
 - 検証失敗は `ValueError` を送出（application 層で捕捉して業務例外に翻訳する）。
 - **形式で振る舞いが変わるなら abstract 基底 + `of()` ファクトリ dispatch**（`ClientId.of(raw)` が `URLClientId` / `RegisteredClientId` に振り分け、`is_("URL")` で判定）。呼び出し側に具体型を意識させない。

## アンチパターン

 - ❌ コマンド/DPO 以外の**ドメイン層で生 `str` / `int` を業務概念として持つ**（primitive obsession）。application の Command は例外的にプリミティブ（`ruleset:application-service` skill）だが、集約フィールド・メソッド引数・戻り値は VO にする。
 - ❌ VO をミュータブルにする / セッターを生やす（VO は差し替えるもの、書き換えるものではない）。
 - ❌ バリデーションを VO の外（application サービスや resource）に散らす。VO の生成に集約する。

## 規範例

### 単純な VO（`init=False` + `super().__setattr__` で自己検証）

```python
MAX_EMAIL_LENGTH = 100


@dataclass(init=False, unsafe_hash=True, eq=True, frozen=True)
class EmailAddress:
    text: str

    def __init__(self, text: str):
        if not text:
            raise ValueError("EmailAddress must not be empty.")
        if len(text) > MAX_EMAIL_LENGTH:
            raise ValueError(f"EmailAddress must be at most {MAX_EMAIL_LENGTH} characters.")
        # re.fullmatch で全体一致を要求し、末尾改行・余剰文字の混入を弾く (メール送信経路への CRLF 注入を防ぐ)。
        if re.fullmatch(r"[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+", text) is None:
            raise ValueError("EmailAddress is invalid.")
        super().__setattr__("text", text)

    def __str__(self) -> str:
        return self.text

    @property
    def domain(self) -> str:
        return self.text.split("@")[1]
```

### ポリモーフィックな VO（abstract 基底 + `of()` で振り分け、サブクラスは `__post_init__` で自己検証）

```python
@dataclass(init=False, frozen=True)
class ClientId(abc.ABC):
    """OAuth 2.1 クライアント識別子を表す Value Object (RFC 6749 §2.2)

    識別形式により 2 経路に分かれる:
      - URLClientId: Client ID Metadata Document URL
      - RegisteredClientId: authorization server に登録された ID (Pre-registration / DCR / RFC 7591)
    """

    value: str

    @staticmethod
    def of(raw: str) -> ClientId:
        """生 str を受け取り、形式に応じて適切なサブクラスに dispatch する。

        呼び出し側 (port 層) がこのファクトリで解決すれば、Application 層はサブクラス具体型を意識せず受け取れる。
        scheme=https の場合は URLClientId.__post_init__ の静的検証で ValueError が送出されうるため、
        呼び出し側で try/except ValueError を巻くこと。
        """
        if urlparse(raw).scheme.lower() == "https":
            return URLClientId(value=raw)
        return RegisteredClientId(value=raw)

    def is_(self, type_: Literal["URL", "Registration"]) -> bool:
        """指定された type に該当するかを判定する"""
        if type_ == "URL":
            return isinstance(self, URLClientId)
        return isinstance(self, RegisteredClientId)


@dataclass(frozen=True)
class URLClientId(ClientId):
    """Client ID Metadata Document の URL 形式クライアント ID"""

    def __post_init__(self) -> None:
        parsed = urlparse(self.value)
        if parsed.scheme.lower() != "https":
            raise ValueError(f"URL client_id must use https scheme: {self.value}")
        if parsed.fragment:
            raise ValueError("URL client_id must not contain a fragment")
        if not parsed.hostname:
            raise ValueError("URL client_id must contain a hostname")

    # 形式固有の振る舞い (例: DNS 解決後の IP 検証) はサブクラスだけに生やす
    def validate(self, resolver: HostnameResolver) -> tuple[str, ...]: ...


@dataclass(frozen=True)
class RegisteredClientId(ClientId):
    """authorization server に登録されたクライアント ID (RFC 6749 §2.2)"""

    def __post_init__(self) -> None:
        if not self.value:
            raise ValueError("client_id must not be empty")
        if urlparse(self.value).scheme.lower() == "https":
            raise ValueError(
                f"https URL client_id must use URLClientId, not RegisteredClientId: {self.value}",
            )
```
