#!/usr/bin/env bash
# Claude Code on the web のセッション開始時に、mise・ツール・lefthook のフックを入れる。
# 各リポジトリの .claude/settings.json の SessionStart hook から、タグを固定して取得・実行する。
# 設計は docs/CLAUDE-WEB-SETUP.md を参照。
set -uo pipefail

# ローカルでは何もしない（ローカルは task init でセットアップする）
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

# Web の既定のネットワークでは mise.run が通らないため、GitHub Releases から入れる
# renovate: datasource=github-release-attachments depName=jdx/mise
MISE_VERSION="v2026.10.4"
MISE_SHA256="2b8ce21f550872807bcaabf45b6bc5c64bfbd6dc3bf49dd4e67de700ef3ceb75"

BIN_DIR="${HOME}/.local/bin"
SHIMS_DIR="${MISE_DATA_DIR:-${HOME}/.local/share/mise}/shims"

warn() { echo "⚠️ claude-web-setup: $*" >&2; }

install_mise() {
  if [ "$("${BIN_DIR}/mise" --version 2>/dev/null | cut -d' ' -f1)" = "${MISE_VERSION#v}" ]; then
    return 0
  fi
  if [ "$(uname -sm)" != "Linux x86_64" ]; then
    warn "対応していないプラットフォームです: $(uname -sm)"
    return 1
  fi

  local tmp
  tmp=$(mktemp) || return 1
  curl -fsSL -o "$tmp" \
    "https://github.com/jdx/mise/releases/download/${MISE_VERSION}/mise-${MISE_VERSION}-linux-x64" &&
    echo "${MISE_SHA256}  ${tmp}" | sha256sum -c --quiet - &&
    mkdir -p "$BIN_DIR" &&
    install -m 755 "$tmp" "${BIN_DIR}/mise"
  local status=$?
  rm -f "$tmp"
  return "$status"
}

main() {
  cd "${CLAUDE_PROJECT_DIR:-.}" || return 1
  [ -f mise.toml ] || { warn "mise.toml がないためスキップします"; return 0; }

  install_mise || { warn "mise を入れられませんでした"; return 1; }

  # mise の postinstall（lefthook install）や後続の確認からツールを呼べるようにする
  export PATH="${SHIMS_DIR}:${BIN_DIR}:${PATH}"

  # ツールは mise.lock の直接ダウンロードの URL から入る（api.github.com はセッション外のリポジトリで 403 になる）
  mise trust . > /dev/null || { warn "mise.toml を信頼できませんでした"; return 1; }
  mise install --yes || { warn "ツールを入れられませんでした"; return 1; }

  # Claude が実行する git commit から lefthook と task を呼べるよう、後続の Bash に PATH を渡す
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    local line="export PATH=\"${SHIMS_DIR}:${BIN_DIR}:\$PATH\""
    # セッションの再開でも実行されるため、同じ行を重ねて書かない
    grep -qxF "$line" "$CLAUDE_ENV_FILE" 2>/dev/null || echo "$line" >> "$CLAUDE_ENV_FILE"
  fi

  # remote の Taskfile を先に取得し、取れないことにセッション開始時に気づけるようにする
  if [ -f Taskfile.yml ]; then
    task --yes --list > /dev/null || { warn "devops の Taskfile を取得できませんでした"; return 1; }
  fi
}

# 失敗してもセッションは止めない（最後の砦は CI の必須チェック）
main || warn "セットアップに失敗しました。pre-commit は動きませんが、PR の CI では必須チェックが動きます"
exit 0
