---
description: アプリケーション層(アプリケーションサービス)の実装方法
summary: アプリケーションサービスは薄い調整役。プライベートメソッド禁止・1メソッド50行以内。取得は DPO、新規作成/更新は Command で単一集約に対して行う
paths:
  - "backend/src/**/application/**/*.py"
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
   - DPOの実装方法: ${CLAUDE_PLUGIN_ROOT}/rules/backend/src/application/dpo.md
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
下記 2 つに触れたら、ロジックの引き上げ先の判断基準として `${CLAUDE_PLUGIN_ROOT}/rules/backend/src/domain/model/domain.md`（ドメイン貧血症）と `${CLAUDE_PLUGIN_ROOT}/rules/backend/src/domain/model/aggregate.md`（不変条件は集約メソッドで守る）を参照する。

 - プライベートメソッド&関数は実装する: アプリケーションサービスでプライベートメソッドおよび関数を実装する/したいケースは、大抵ドメイン層配下のドメインオブジェクトのメソッドとして定義すべきドメインロジックがアプリケーションサービスに漏れている時である。
 - メソッドが50行よりも長くなる: 収められないケースは「ドメインオブジェクトのメソッド化が漏れている」「必要なドメインオブジェクトが欠落している」ときである。ドメイン層の実装を見直してください。 

## メソッド

 - 新規作成/更新系は特別な理由がない限り**1つの `save` メソッド**を提供するように実装してください。
   - こうすることで、集約の作成/更新項目が増えたり減ったりしてもこの `save` メソッド内のみ変更すれば良いので、メンテナンスしやすくなります

## 参考

**アプリケーションサービス**

 - backend/src/authority/application/identity/identity_application_service.py
 - backend/src/apigateway/application/authentication/authentication_application_service.py

**コマンド**

 - backend/src/authority/application/identity/command.py
