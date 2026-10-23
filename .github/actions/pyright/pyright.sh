#!/usr/bin/env bash
# プロジェクト（カレントディレクトリ）の環境で Pyright を実行する。
# 検査対象と厳しさは、このプロジェクトの [tool.pyright] / pyrightconfig.json に委ねる
# （位置引数を渡すと設定の include が無視される。mypy と同じく、workspace のメンバーの設定は読まれない）。
# -p .: このディレクトリに設定があればそれを使う（無ければ親の pyrightconfig.json が使われるため、下で書き出す）。
# Pyright の wheel は本体を同梱しており、Node.js はランナーのものを使う（実行時に npm から取得しない）
set -euo pipefail

# 別の uv.lock を持つ入れ子のプロジェクト（自分の matrix で検査される）。どれがどの uv.lock に属するかは python-targets が決める
nested=$(jq -c --arg project "${PROJECT}" '.[$project] // []' <<< "${NESTED}")
# 設定の有無は、pyproject.toml を TOML として読み（サブテーブル・ドット付きのキーなど、どの書き方でも拾う）、setup.cfg は見出しの行を探して判定する。
# ランナーの Python（3.11 以上）で読む。-I: カレントディレクトリ（対象 repo）のモジュールを import しない。
# 終了コード: 0 = ある、10 = 無い、それ以外 = 読めなかった
has_tool() { # <pyproject.toml の [tool] の下の名前>
  [ -e pyproject.toml ] || return 10
  python3 -I -c 'import sys, tomllib; sys.exit(0 if sys.argv[1] in tomllib.load(open("pyproject.toml", "rb")).get("tool", {}) else 10)' "$1"
}
has_mypy_cfg() { # setup.cfg の [mypy] / [mypy-xxx]。configparser が読めない書き方（見出しの前の行など）でも拾えるよう、見出しの行を探す
  [ -e setup.cfg ] || return 10
  python3 -I -c 'import re, sys; sys.exit(0 if any(re.match(r"\s*\[mypy(-[^]]*)?\]", line) for line in open("setup.cfg", encoding="utf-8", errors="replace")) else 10)'
}
# 利用者の設定があれば書き換えない（入れ子のプロジェクトを除くかも利用者に任せ、落ちたときに案内する）
generated=false
if [ -e pyrightconfig.json ]; then
  config="pyrightconfig.json"
else
  # pyrightconfig.json が無ければ [tool.pyright] が読まれる。案内もそこを指す
  config="pyproject.toml の [tool.pyright]"
  pyright_config=0
  has_tool pyright || pyright_config=$?
  if [ "${pyright_config}" -ne 0 ] && [ "${pyright_config}" -ne 10 ]; then
    # 読めないときは、利用者の [tool.pyright] を上書きしないよう設定を書き出さない
    echo "::warning::Pyright: pyproject.toml を読めませんでした。[tool.pyright] があるか判定できないため、そのまま検査します"
  fi
  if [ "${pyright_config}" -eq 10 ]; then
    if [ -e mypy.ini ] || [ -e .mypy.ini ] || has_tool mypy || has_mypy_cfg; then
      echo "::warning::Pyright: mypy の設定は使われません。検査対象や厳しさは pyproject.toml の [tool.pyright] に移してください（https://microsoft.github.io/pyright/#/configuration）"
    fi
    # 設定が無いと、-p . でも親ディレクトリの pyrightconfig.json が使われ、ディレクトリ全体が検査される。
    # このプロジェクトの設定を書き出し、入れ子のプロジェクトを除く（既定の除外 node_modules・隠しディレクトリなどは残る）
    jq -n --argjson nested "${nested}" '{exclude: $nested}' > pyrightconfig.json
    generated=true
  fi
fi
# 一度だけ導入し、導入の失敗を型エラー（exit 1）と取り違えないようにする。
# 実行はプロジェクトの環境（uv run）で行い、import をプロジェクトの依存で解決させる
if ! uv tool install --quiet "pyright==${PYRIGHT_VERSION}"; then
  echo "::error::Pyright: pyright ${PYRIGHT_VERSION} を導入できませんでした。上の uv のエラーを確かめてください"
  exit 1
fi
pyright="$(uv tool dir --bin)/pyright"
log=$(mktemp)
status=0
# 存在しないパスの警告などは標準エラーに出るため、ログに入れる。--stats: 検査したファイルの数を出させる（0 件の判定に使う）
uv run --no-sync "${pyright}" -p . --stats 2>&1 | tee "${log}" || status=$?
# Pyright は include のパスが無くても 0 で終わる。何も検査しないまま通らないよう落とす（mypy も落ちていた）
if [ "${status}" -eq 0 ] && grep -q ' does not exist\.$' "${log}"; then
  echo "::error::Pyright: ${config} の include に存在しないパスがあります。検査されないファイルが出ないよう直してください（https://microsoft.github.io/pyright/#/configuration）"
  exit 1
fi
# 設定の打ち間違い（知らない設定・不正な値・executionEnvironments の中の誤り）も、Pyright はその設定を無視して検査し、型エラーが無ければ 0 で終わる。
# "$schema"（エディタの補完に使う JSON Schema のキー）は Pyright が知らない設定として出すが、正しい設定なので除く
# shellcheck disable=SC2016 # "$schema" は展開せず、そのままの文字列として探す
if grep -E '^Config (contains unrecognized setting|"|executionEnvironments index [0-9]+: )' "${log}" | grep -vqF 'unrecognized setting "$schema"'; then
  echo "::error::Pyright: ${config} に、知らない設定か不正な値があります。上の Config の行を確かめて直してください（https://microsoft.github.io/pyright/#/configuration）"
  [ "${status}" -ne 0 ] || exit 1
fi
# 利用者の設定で検査するファイルが 1 つも無いときも 0 で終わる（mypy は落ちていた）。
# 書き出した設定では、コードがすべて入れ子のプロジェクトにあり 0 件のことがあるため落とさない。
# include の項目ごとの 0 件（ほかの項目にファイルがある）は、項目ごとの一覧が要るため見ない。
# これらの判定は Pyright の出力の文言に頼るため、PYRIGHT_VERSION を上げたら文言が変わっていないか確かめる
if [ "${status}" -eq 0 ] && [ "${generated}" = false ] && grep -q '^No source files found\.$' "${log}"; then
  echo "::error::Pyright: ${config} の include / exclude に当てはまる Python ファイルがありません。検査されないファイルが出ないよう直してください（https://microsoft.github.io/pyright/#/configuration）"
  exit 1
fi
# ラッパー（pyright-python）が Pyright を起動できないときも 1 で終わる。Pyright は必ず集計の行を出すため、無ければ実行時のエラーとして扱う
if [ "${status}" -eq 1 ] && ! grep -qE '^[0-9]+ errors?, [0-9]+ warnings?, [0-9]+ informations?$' "${log}"; then
  status=2
fi
case "${status}" in
  0) ;;
  1)
    keep=""
    if [ "${generated}" = true ] && [ "${nested}" != "[]" ]; then
      # 書き出した設定にしか入れ子のプロジェクトの除外が無いため、利用者が設定を書くときに残すよう伝える
      keep="（設定を書くときは、入れ子のプロジェクト $(jq -r 'join(", ") | gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A")' <<< "${nested}") も exclude に入れてください）"
    fi
    echo "::error::Pyright: 型エラーを直してください。検査から外すディレクトリ（scripts/ など）は ${config} の include / exclude で絞れます${keep}（https://microsoft.github.io/pyright/#/configuration）"
    # 入れ子のプロジェクトのファイルに指摘があれば、このプロジェクトの環境で検査されている（除外できていない）
    unchecked=$(jq -c --arg pwd "${PWD}" --rawfile log "${log}" '[.[] | select(. as $dir | $log | split("\n") | any(contains($pwd + "/" + $dir + "/") and test(" - (error|warning): ")))]' <<< "${nested}")
    if [ "${unchecked}" != "[]" ]; then
      # パスは対象 repo 由来のため、ワークフローコマンドとしてエスケープする
      echo "::error::Pyright: 入れ子のプロジェクト（$(jq -r 'join(", ") | gsub("%"; "%25") | gsub("\r"; "%0D") | gsub("\n"; "%0A")' <<< "${unchecked}")）が、このプロジェクトの環境で検査されています。${config} の exclude に入れてください（それぞれ自分の環境で検査されます）"
    fi
    ;;
  *) echo "::error::Pyright: 型チェックを実行できませんでした（exit ${status}）。上のエラーと、${config} の書き方を確かめてください（https://microsoft.github.io/pyright/#/configuration）" ;;
esac
exit "${status}"
