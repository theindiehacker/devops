#!/usr/bin/env bash
# アプリケーションコードを Semgrep CE（SAST, ルールセット p/default・severity ERROR のみ）でスキャンする。
# --baseline-commit により「PR で新規に増えた検出」のみを対象とするため、既存コードの検出が無関係な PR をブロックすることはない
set -euo pipefail

# コンテナは root で動くため、runner が checkout した作業ツリーを git に信頼させる（--baseline-commit が git を使う）。
# --disable-nosem: インライン nosemgrep コメントを無効化（抑制は承認必須の .semgrepignore に限定する）
docker run --rm \
  --volume "${GITHUB_WORKSPACE}:/src" --workdir /src \
  --env GIT_CONFIG_COUNT=1 --env GIT_CONFIG_KEY_0=safe.directory --env GIT_CONFIG_VALUE_0=/src \
  "${IMAGE}" \
  semgrep scan \
  --config p/default \
  --severity ERROR \
  --error \
  --metrics off \
  --disable-version-check \
  --disable-nosem \
  --baseline-commit "${BASELINE}" \
  .
