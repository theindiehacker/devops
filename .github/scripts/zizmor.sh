#!/usr/bin/env bash
# GitHub Actions のワークフロー / action 定義（と zizmor が収集する dependabot.yml / pre-commit 設定）を zizmor で静的解析し、
# severity HIGH 以上の検出で失敗する。.github/Taskfile.yml の zizmor タスクから、検査対象リポジトリのルートで実行される。
#
# GH_TOKEN があれば online 監査（impostor-commit / known-vulnerable-actions 等）も行う（CI）。無ければ offline で行う（ローカル）。
set -euo pipefail

# zizmor がスキャンする種類（`zizmor .` の収集対象と同じ: workflow / action / dependabot / pre-commit。後者 2 つは
# ファイル名だけで判定され任意のディレクトリから収集される）の git pathspec。
# 必須ワークフロー（.github/workflows/zizmor.yml）の paths-filter とも揃えること
pathspecs=(
  ':(glob).github/workflows/*.yml' ':(glob).github/workflows/*.yaml' ':(glob)**/action.yml' ':(glob)**/action.yaml'
  ':(glob)**/dependabot.yml' ':(glob)**/dependabot.yaml'
  ':(glob)**/.pre-commit-config.yaml' ':(glob)**/.pre-commit-config.yml' ':(glob)**/.pre-commit-hooks.yaml' ':(glob)**/.pre-commit-hooks.yml'
)

# 対象はリポジトリ全体（未コミットの新規ファイルも含む）。
# 列挙はファイル経由にし、git の失敗を set -e で検知する（プロセス置換の中の失敗は set -e の対象外）。
# core.quotePath=false: 非 ASCII パスがクォートされて zizmor にリモート入力と誤解されるのを防ぐ
list=$(mktemp)
trap 'rm -f "${list}"' EXIT
git -c core.quotePath=false ls-files --cached --others --exclude-standard -- "${pathspecs[@]}" > "${list}"
targets=()
while IFS= read -r t; do
  # 削除済み（未ステージ）の tracked ファイルは除く
  # ./ を付ける: `--config=x/action.yml` のような - 始まりのパスを zizmor にオプションとして解釈させない
  if [ -f "${t}" ]; then targets+=("./${t}"); fi
done < "${list}"

if [ "${#targets[@]}" -eq 0 ]; then
  echo "zizmor: 対象ファイルがありません"
  exit 0
fi

# zizmor の --no-ignores は承認必須の .github/zizmor.yml による抑制まで無効化してしまうため、
# インラインコメントのトークンの存在自体を禁止する（抑制は .github/zizmor.yml に限定する）
if grep -HnE 'zizmor:[[:space:]]*ignore' -- "${targets[@]}"; then
  echo "インラインの zizmor ignore コメントは使用できません。.github/zizmor.yml で抑制してください（変更にはセキュリティチームの承認が必要）"
  exit 1
fi

# 設定ファイルの自動探索はリポジトリ直下や入力ファイルの祖先ディレクトリの zizmor.yml / zizmor.yaml
# にも及び、承認必須（docs/SETUP.md 2.5）の対象外パスから検出を抑制できてしまうため、
# 承認必須の .github/zizmor.yml に固定する（未作成なら設定なしで実行する）
config_args=(--no-config)
if [ -f .github/zizmor.yml ]; then
  config_args=(--config .github/zizmor.yml)
fi

online=()
offline=()
if [ -z "${GH_TOKEN:-}" ]; then
  # トークンが無い（ローカル）場合は online 監査を行わない。online 監査は CI で担保する
  offline=("${targets[@]}")
  offline_args=(--offline)
else
  offline_args=(--no-online-audits)
  owner="${GITHUB_REPOSITORY_OWNER:-theindiehacker}"
  api_url="${GITHUB_API_URL:-https://api.github.com}"

  # 本リポジトリ（<org>/devops）が private だと、対象リポジトリの github.token では参照先を読めず、
  # 本リポジトリの reusable workflow を参照するファイル（Claude レビューの caller 等）の impostor-commit が
  # findings ではなく fatal で終了する（#21）。そこで実行トークンで本リポジトリを読めるかを先に確認し、
  # 読めるなら全件 online、読めない場合だけ本リポジトリのみを参照するファイルを online 監査なしで実行する。
  # fork 禁止の private リポジトリには fork 由来の impostor commit が成立せず、ブランチ / タグに属さない SHA の検知は
  # github.token ではどのみち監査できないため、この省略で新たに失う検知は無い。
  # 他の action を 1 つでも参照するファイルは online で監査するため、免除を抜け道にはできない。
  # TODO: zizmor に特定リポジトリを除外する設定が入ったら .github/zizmor.yml に乗り換える
  #       https://github.com/zizmorcore/zizmor/issues/1350
  if curl -fs -o /dev/null -H "Authorization: Bearer ${GH_TOKEN}" "${api_url}/repos/${owner}/devops"; then
    online=("${targets[@]}")
    targets=()
  fi
  # 振り分けには mikefarah/yq（ubuntu-latest に同梱）が必要。無い / 別実装（Python 版 yq 等）だと解析失敗として
  # 全件が黙って online に倒れ、原因表示なしで fatal になるため、ツールの不在は明示的に失敗させる
  if [ "${#targets[@]}" -gt 0 ] && ! { yq --version 2>/dev/null | grep -q 'mikefarah/yq'; }; then
    echo "mikefarah/yq が見つかりません（${owner}/devops を参照するファイルの振り分けに必要）"
    exit 1
  fi
  # 旧名（github-workflows）は改名前の参照が残る caller 用。全 caller の移行後に削除する
  self_ref="^${owner}/(devops|github-workflows)/"
  # ${arr[@]+...}: 空配列でも set -u で落ちないようにする（macOS 標準の bash 3.2 対策）
  for t in ${targets[@]+"${targets[@]}"}; do
    # YAML を解析して uses: の値を再帰的に集める（flow 形式・引用符付きキー・アンカーも対象。zizmor と同じ見え方にする）。
    # 解析に失敗したファイルは refs が空になり online 側に倒れる（fatal で気付ける安全側）
    refs=$(yq -r '[explode(.) | .. | select(tag == "!!map" and has("uses")) | .uses] | .[]' "${t}" 2>/dev/null \
      | grep -vE '^(\./|docker://|\$/)' || true)
    # owner / repo 名は大文字小文字を区別しない
    if [ -n "${refs}" ] && ! grep -qivE "${self_ref}" <<< "${refs}"; then
      offline+=("${t}")
      echo "${t}: ${owner}/devops のみを参照するため online 監査を省略しました（理由は devops の .github/scripts/zizmor.sh を参照）"
    else
      online+=("${t}")
      # 本リポジトリと他の action の参照が混在すると online 側で generic な fatal になるため、原因を先に示す
      if grep -qiE "${self_ref}" <<< "${refs}"; then
        echo "${t}: ${owner}/devops と他の action の参照が混在しています。devops を読めないため、このファイルの online 監査（impostor-commit）は fatal になります。devops の参照は別ファイルに分けてください"
      fi
    fi
  done
fi

# AI が読む前提で plain 形式・ANSI カラーなし・進捗ログなしで出力する。
# exit code は zizmor のもの（1: エラー / 14: 検出 等）を保持する
# zizmor 1.30 は pre-commit 設定を収集しないため、pre-commit 設定しか無いと「no inputs collected」で exit 3 になる。
# これは検査対象が無いだけなので成功扱いにする
out=$(mktemp)
trap 'rm -f "${list}" "${out}"' EXIT
rc=0
run_zizmor() {
  local r=0
  zizmor --quiet --no-progress --color never --min-severity high "${config_args[@]}" "$@" > "${out}" 2>&1 || r=$?
  cat "${out}"
  if [ "${r}" -eq 3 ] && grep -q 'no inputs collected' "${out}"; then
    echo "zizmor: 監査できる入力が無いため skip しました"
    r=0
  fi
  if [ "${r}" -ne 0 ]; then rc=${r}; fi
}
if [ "${#online[@]}" -gt 0 ]; then run_zizmor "${online[@]}"; fi
if [ "${#offline[@]}" -gt 0 ]; then run_zizmor "${offline_args[@]}" "${offline[@]}"; fi
exit "${rc}"
