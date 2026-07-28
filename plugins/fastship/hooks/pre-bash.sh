#!/usr/bin/env bash
# https://code.claude.com/docs/ja/hooks-guide
# --no-verify の禁止 (フック・signing をバイパスしない)
# ローカル terraform apply/destroy の禁止 (GitHub Actions から実行する)

set -euo pipefail

event=$(cat)
command=$(echo "$event" | jq -r '.tool_input.command // empty')

if [[ -z "$command" ]]; then
  exit 0
fi

if echo "$command" | grep -qE -- '(^|[[:space:]])--no-verify([[:space:]]|$)'; then
  cat >&2 <<'EOF'
🚫 --no-verify は禁止されています。

【理由】
Git pre-commit / pre-push フックは品質・型・テストの最終ゲート。バイパスすると CI で
落ちるコードや本番事故を引き起こす変更が main に入る。

【失敗時の対処】
1. 失敗したフックのエラーメッセージを読む
2. 該当ファイルを修正
3. 再 commit / push を試みる

緊急回避が本当に必要な場合のみ、ユーザーに明示的に許可を求める。
EOF
  exit 2  # exit 2 = アクションをブロック
fi

if echo "$command" | grep -qE '(^|[[:space:]])terraform[[:space:]]+(apply|destroy)([[:space:]]|$)'; then
  cat >&2 <<'EOF'
🚫 terraform apply / destroy のローカル実行は禁止です。

【理由】
本番インフラ変更は GitHub Actions の PR レビュー + approval ゲートを経由する設計。
ローカル apply は (1) コードに残らない drift を生む (2) state ロックの race を起こす
(3) 監査ログに残らない、ため。

【代替手順】
1. Terraform 変更を PR にする
2. GitHub Actions で terraform plan の結果を確認
3. レビューを得て merge → CI で apply される
EOF
  exit 2
fi

exit 0
