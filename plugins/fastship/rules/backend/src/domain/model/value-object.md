---
description: 値オブジェクト (Value Object) の設計/実装方法
summary: 業務概念を生 str/int で引き回さず VO 化する(primitive obsession 撲滅)。VO は不変・値等価・自己検証で不正値は生成不可。取り違えると事故る ID は別々の VO
paths:
  - "backend/src/**/domain/model/**/*.py"
---
# 値オブジェクト (Value Object)

「概念に名前と制約と振る舞いを与える」ための不変オブジェクト。**primitive obsession（`str` / `int` の生値を業務概念のまま引き回すこと）を撲滅する**のが目的。

規範例:
 - 単純: `backend/src/common/domain/model/mail/email_address.py`（`EmailAddress`）
 - ポリモーフィック（形式で分岐）: `backend/src/authority/domain/model/client/client_id.py`（`ClientId` → `URLClientId` / `RegisteredClientId`）
 - 共有 VO は `backend/src/common/domain/model/` 配下（`AppId` / `PoolId` / `EmailAddress` / `URL` / `Amount` 等）。**複数モジュールで共有する ID・業務概念だけ common に置く**（業務語彙を common に溜めない）。

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

 - ❌ コマンド/DPO 以外の**ドメイン層で生 `str` / `int` を業務概念として持つ**（primitive obsession）。application の Command は例外的にプリミティブ（`${CLAUDE_PLUGIN_ROOT}/rules/backend/src/application/application.md`）だが、集約フィールド・メソッド引数・戻り値は VO にする。
 - ❌ VO をミュータブルにする / セッターを生やす（VO は差し替えるもの、書き換えるものではない）。
 - ❌ バリデーションを VO の外（application サービスや resource）に散らす。VO の生成に集約する。
