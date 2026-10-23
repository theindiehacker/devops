#!/usr/bin/env bash
# バンドルサイズの計測対象を規約で検出し、出力 frontends / targets に書く:
#   - package.json の依存に next / astro を持ち、同じディレクトリに bun.lock / bun.lockb があるディレクトリ
#     （bun.lock が無いと compressed-size-action は npm install を使うため、workspace の子などは計測しない）
#   - PR がそのディレクトリ配下を変更していなければ、2 回のビルドを省くため計測しない
#     （フロントエンドが repo のルートにあると、どのファイルを変えても計測する）
set -euo pipefail

# package.json の依存から、計測するファイルを決める（next / astro が無ければ対象外）。
# ファイル名のハッシュは伏せない。Turbopack のチャンク名はハッシュだけで、Astro（Vite）は同じ名前のチャンクを
# 複数出すことがあり、伏せると別のファイルが同じ名前になって合計が合わなくなるため
# shellcheck disable=SC2016 # $deps / $dir / $changed は jq の変数
frameworks='
  (.dependencies + .devDependencies) as $deps
  | if $deps.next then ".next/static/chunks/**/*.{js,css}"
    elif $deps.astro then "dist/**/*.{js,css}"
    else empty end
  | {dir: $dir, pattern: ., changed: $changed}'

# git ls-files はコミットされたファイルだけを返すため、node_modules は対象にならない。
# JSON として読めない package.json は飛ばす（jq の失敗で判定が失敗し、マージを止めないようにする）。
# key は artifact の名前に使う通し番号（ディレクトリ名から作ると、別のディレクトリが同じ名前になり得るため）
all=$(git -c core.quotePath=false ls-files ':(glob)**/package.json' | while IFS= read -r pkg; do
  dir=$(dirname "${pkg}")
  if [ -e "${dir}/bun.lock" ] || [ -e "${dir}/bun.lockb" ]; then
    changed=true; git diff --quiet HEAD^1 HEAD -- "${dir}" && changed=false
    jq -c --arg dir "${dir}" --argjson changed "${changed}" "${frameworks}" "${pkg}" || true
  fi
done | jq -sc 'to_entries | map(.value + {key: "\(.key)"})')
jq -r '"frontends=\(length > 0)", "targets=\(map(select(.changed)) | tojson)"' <<< "${all}" | tee -a "${GITHUB_OUTPUT}"
