#!/usr/bin/env bash
# https://code.claude.com/docs/ja/hooks-guide
# --no-verify の禁止 (フック・signing をバイパスしない)
# ローカル terraform apply/destroy の禁止 (GitHub Actions から実行する)

set -uo pipefail

# このフックは「止めるため」に在るので、検査できない状態は素通しではなくブロックに倒す。
# (jq 不在で set -e により exit 127 すると、非ブロッキング扱いになり禁止コマンドが通ってしまう)
if ! command -v jq >/dev/null 2>&1; then
  echo "🚫 jq が無いためコマンドを検査できません。jq を入れてください (brew install jq / apt install jq)。" >&2
  exit 2
fi

event=$(cat)
if ! command=$(printf '%s' "$event" | jq -r '.tool_input.command // empty'); then
  echo "🚫 hook 入力の JSON を解析できず、コマンドを検査できませんでした。" >&2
  exit 2
fi

if [[ -z "$command" ]]; then
  exit 0
fi

# 検査対象は「引用符の外側」だけにする。コミットメッセージ本文に --no-verify と書いただけで
# ブロックされる誤爆 (このプラグイン自身の説明コミットなど) を避けるため。
sep='[[:space:];&|)]'
scan=$(printf '%s' "$command" | sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g')

# `;` `&&` `||` `|` で区切られた各コマンドを 1 行ずつに割る。判定を 1 セグメントに閉じないと、
# `git commit -m x && grep -n TODO` のような複合コマンドで、無関係な -n を git のものと
# 誤認してブロックしてしまう。
segments=$(printf '%s' "$scan" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/[;&|]/\n/g')

# `git commit -n` / `git push -n` は --no-verify と同じ効果なので同列に扱う。
# grep -n / head -n のような他コマンドの -n は、セグメントが分かれているので巻き込まない。
if echo "$segments" | grep -qE -- "(^|[[:space:]])--no-verify([[:space:]]|$)" ||
  echo "$segments" | grep -qE "^[[:space:]]*git([[:space:]]+-[^[:space:]]+)*[[:space:]]+(commit|push)([[:space:]].*)?[[:space:]]-n([[:space:]]|$)" ||
  echo "$scan" | grep -qE -- "core\.hooksPath[[:space:]]*="; then
  cat >&2 <<'EOF'
🚫 Git フックのバイパス (--no-verify / -n / core.hooksPath 上書き) は禁止されています。

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

# terraform -chdir=infra apply のように、サブコマンドの前にフラグが挟まる形も捕まえる。
# tofu (OpenTofu) は terraform のドロップイン代替なので同じ扱いにする。
if echo "$segments" | grep -qE "^[[:space:]]*(terraform|tofu)([[:space:]]+-[^[:space:]]+)*[[:space:]]+(apply|destroy)([[:space:]]|$)"; then
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
