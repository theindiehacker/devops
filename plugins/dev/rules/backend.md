---
description: Backend の実装ルール
summary: Backend は DDD と SOLID で実装する。ドメインモデルの詳細は domain/model 配下のルールに従う
paths:
  - "backend/**/*"
---
# 実装ルール

> このファイル群 (dev プラグイン同梱の規約) の中での相互参照は、すべて**プラグインルート相対**
> (`rules/...`) で書いている。全文を読むときは、rules-guard フックが「正:」として注入した絶対パス、
> または現在読んでいるルールファイルの絶対パスから同じ `rules/` 配下を辿ること。
> プロジェクトの `.claude/rules/` に同じ相対パスのファイルがあれば、そちらが優先される。

 - ドメイン駆動設計(DDD)の設計/実装方法を守ってください
   - 参照: rules/backend/src/domain/model
 - SOLID原則の守って実装してください
