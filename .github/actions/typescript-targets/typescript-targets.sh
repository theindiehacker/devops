#!/usr/bin/env bash
# TypeScript の検査対象を規約で検出し、出力 roots / tsconfigs / nextjs に JSON 配列で書く:
#   - 導入単位 = 祖先に package.json を持たない最上位の package.json のディレクトリ。monorepo（workspaces）
#     ではルート 1 箇所、frontend/ と tools/ のように独立プロジェクトが並ぶ構成では各々が単位になる
#   - 型チェック単位 = tsconfig.json のあるディレクトリ（workspace ごとの tsconfig.json も個別に検査する）
#   - node_modules / .git は探索対象外
set -euo pipefail

# 導入単位。package.json を見つけた時点で -prune し、その配下は単位として数えない
find . \( -path ./.git -o -name node_modules \) -prune -o \
  -type d -exec test -e '{}/package.json' ';' -print -prune \
  | sed 's|^\./||' | sort > "${RUNNER_TEMP}/roots.txt"
# 型チェック単位（-printf '%h' は tsconfig.json のあるディレクトリ）
find . \( -path ./.git -o -name node_modules \) -prune -o \
  -name tsconfig.json -printf '%h\n' \
  | sed 's|^\./||' | sort > "${RUNNER_TEMP}/tsconfigs.txt"
# 型チェック単位のうち、package.json の依存に next を持つもの (Next.js のプロジェクト)
while IFS= read -r dir; do
  if jq -e '.dependencies.next // .devDependencies.next' "${dir}/package.json" > /dev/null 2>&1; then
    echo "${dir}"
  fi
done < "${RUNNER_TEMP}/tsconfigs.txt" > "${RUNNER_TEMP}/nextjs.txt"

for name in roots tsconfigs nextjs; do
  echo "${name}=$(jq -Rsc 'split("\n")[:-1]' "${RUNNER_TEMP}/${name}.txt")" | tee -a "${GITHUB_OUTPUT}"
done
