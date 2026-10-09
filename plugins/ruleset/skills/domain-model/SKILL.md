---
name: domain-model
description: ドメイン層の実装方法 (DDD ハンドブック索引)。ドメイン貧血症を避ける。ユビキタス言語の動詞は集約メソッドになる。application 層のプライベートメソッドや50行超はロジック漏れの兆候
paths:
  # application も含める: 貧血ドメインは「domain を触らず application に全ロジックを書く」形で
  # 起きるため、domain スコープだけだとその瞬間に本ルールがロードされない。
  - "backend/src/**/domain/model/**/*.py"
  - "backend/src/**/application/**/*.py"
user-invocable: false
---
# ドメイン層
このリポジトリでは、ドメイン駆動設計(DDD)に基づいて設計・実装してください。

## DDD ハンドブック（このディレクトリの他ファイル）

ドメインモデルを設計/実装/レビューするときは、以下も併せて参照する（`/design` は着手前に明示的に読み込む）:

 - 集約・エンティティ: `ruleset:aggregate` skill（境界の切り方・不変条件・ID 参照）
 - 値オブジェクト: `ruleset:value-object` skill（primitive obsession 撲滅・自己検証）
 - ドメインイベント: `ruleset:domain-event` skill（プレーン/集約跨ぎの伝播）
 - リポジトリ: `ruleset:repository` skill（1 集約 = 1 リポジトリ・境界キー強制）
 - ドメインサービス: `ruleset:domain-service` skill（使いどころ・ファクトリとしての ACL / 腐敗防止層）
 - 本ファイル: ドメイン貧血症の回避（下記）

## ドメイン貧血症 (Anemic Domain Model) を避ける（最重要）

**ユビキタス言語の "動詞" は集約/エンティティのメソッドになる**。「顧客が姓名を変える」なら、`Customer` に `姓`/`名` を公開するだけでなく `rename(...)` を実装する。次の兆候はロジックがドメイン層から漏れているサイン:

 - 集約/VO がプロパティ（ゲッター/セッター）だけで**振る舞いメソッドが無い**。
 - **アプリケーションサービスにプライベートメソッドがある / メソッドが 50 行を超える**（`ruleset:application-service` skill）。その手続きは集約メソッドに引き上げる。
 - application サービスが集約フィールドを直接組み立てて不変条件を作っている（集約メソッド化する。実例の強い形は `user.py` の `reset_password` / `verified` / `unlink`）。
