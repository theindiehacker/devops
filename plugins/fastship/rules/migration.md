---
description: データベースモデルやマイグレーション関連の変更時に適用
summary: マイグレーションは task migration:generate で自動生成し内容を目視確認する。データ損失を伴う変更は特に慎重に。テーブル追加時は core.py の tables に登録
paths:
  - "backend/src/**/persistence/**/*.py"
  # 素のディレクトリパスはディレクトリ自身にしかマッチしないため配下全体を指定する
  - "backend/migration/**/*"
  - "backend/alembic.ini"
---

# データベースマイグレーションルール

## マイグレーション作成手順

1. ドメインモデル（`domain/model/`）を変更
2. 永続化層（`port/adapter/persistence/`）の SQLAlchemy モデルを更新
3. マイグレーションを自動生成: `task migration:generate`
4. 生成されたマイグレーションファイルの内容を確認
5. マイグレーション適用: `task migration:upgrade`

## 注意事項

- マイグレーションファイルは自動生成後、必ず内容を目視確認すること
- データ損失を伴う変更（カラム削除、型変更）は特に慎重に確認
- 空のマイグレーションが必要な場合は `task migration:revision` を使用
- マイグレーションファイルのコメントは日本語で記載
- テーブルクラスを追加した場合、対応モジュールの `core.py` で `tables` プロパティにドライバーモジュールパスを追加すること