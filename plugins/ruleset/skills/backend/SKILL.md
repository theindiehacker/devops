---
name: backend
description: Backend の実装ルール。Backend は DDD と SOLID で実装する。ドメインモデルの詳細は domain/model 配下のルールに従う
paths:
  - "backend/**/*"
user-invocable: false
---
# 実装ルール

 - ドメイン駆動設計(DDD)の設計/実装方法を守ってください
   - 参照: `ruleset:domain-model` skill（集約・値オブジェクト・ドメインイベント・リポジトリ・ドメインサービスの索引）
 - SOLID原則の守って実装してください
