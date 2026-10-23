#!/usr/bin/env bash
# バンドルサイズの計測結果を PR にコメントする
set -euo pipefail

# artifact が無い対象（ビルドの失敗、タイムアウトなど）は「計測できませんでした」にする
body="${RUNNER_TEMP}/bundle-size-body.md"
jq -r '.[] | "\(.key)\t\(.dir)"' <<< "${TARGETS}" | while IFS=$'\t' read -r key dir; do
  printf '### 📦 %s\n\n' "${dir}"
  cat "${RESULTS}/bundle-size-${key}.md" 2>/dev/null \
    || printf '⚠️ 計測できませんでした（ビルドの失敗やタイムアウトなど）。[ログ](%s)\n' "${RUN_URL}"
  echo
done > "${body}"
[ -s "${body}" ] || echo "このコミットではフロントエンドを変えていないため、バンドルサイズを計測していません。" > "${body}"

# 前回のコメント（github-actions[bot] が書いた、目印のあるもの）を更新する。
# 計測していないのに前回のコメントも無いときは、何も書かない
text="$(cat "${body}")"$'\n\n'"${MARKER}"
id=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${PR}/comments" --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | contains(env.MARKER))) | .id' | tail -n 1)
if [ -n "${id}" ]; then
  gh api --method PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${id}" -f body="${text}" > /dev/null
elif [ "${TARGETS}" != "[]" ]; then
  gh api --method POST "repos/${GITHUB_REPOSITORY}/issues/${PR}/comments" -f body="${text}" > /dev/null
fi
