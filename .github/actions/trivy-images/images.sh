#!/usr/bin/env bash
# security.yml の scan-image でビルドしてスキャンするイメージを決め、matrix に渡す JSON 配列を出力 images に書く。
#   - .github/trivy-image.yml があれば、列挙された image だけをビルドする
#   - 無ければ Dockerfile / Dockerfile.* / *.Dockerfile を自動検出し、置き場所を build context に、
#     最終ステージ (ほかのステージから FROM・COPY --from・RUN --mount の from= で使われないステージ) をすべて target にする。
#     最後のステージ (ビルドの既定) は、参照の解釈によらず必ず含める
set -euo pipefail

# Dockerfile の COPY・ADD の --from= と、RUN の --mount の from= に書かれた参照 (ステージ名か番号) を 1 行に 1 つ出す。
# 命令の引数の文字列 (RUN echo --from=api など) を参照と取り違えないよう、BuildKit と同じく
# パーサーディレクティブの escape・コメント行・継続行・ヒアドキュメントを解釈し、命令の先頭のフラグだけを見る
from_refs() {
  local escape="\\" directives=true instruction="" line end word words continuation heredocs=()
  while IFS= read -r line || [ -n "${line}" ]; do
    # ヒアドキュメントの中身は命令ではない。終わりの行まで読み飛ばす (<<- は終わりの行の先頭のタブを無視する)
    if [ "${#heredocs[@]}" -gt 0 ]; then
      end=${heredocs[0]}
      if [ "${end:0:1}" = "-" ]; then end=${end:1}; line=${line#"${line%%[!$'\t']*}"}; fi
      if [ "${line}" = "${end}" ]; then heredocs=("${heredocs[@]:1}"); fi
      continue
    fi
    # パーサーディレクティブは先頭の「# key=value」の行だけ。escape で継続行の記号が変わる
    if ${directives} && [[ ${line} =~ ^#[[:space:]]*([A-Za-z]+)[[:space:]]*=[[:space:]]*([^[:space:]]*) ]]; then
      if [ "${BASH_REMATCH[1],,}" = escape ]; then escape=${BASH_REMATCH[2]:0:1}; fi
      continue
    fi
    directives=false
    # コメント行と空行 (継続行の途中も含む) は、BuildKit と同じく命令に含めない
    if [[ ${line} =~ ^[[:space:]]*(#|$) ]]; then continue; fi
    continuation="[${escape}][[:space:]]*\$"
    if [[ ${line} =~ ${continuation} ]]; then
      instruction+="${line%"${escape}"*} "
      continue
    fi
    instruction+=${line}
    read -ra words <<<"${instruction}"
    instruction=""
    case "${words[0]^^}" in COPY | ADD | RUN) ;; *) continue ;; esac
    for word in "${words[@]:1}"; do
      [ "${word:0:2}" = "--" ] || break
      case "${word,,}" in
        --from=*) echo "${word#*=}" ;;
        --mount=*) tr ',' '\n' <<<"${word#*=}" | sed -n 's/^from=//p' ;;
      esac
    done
    # この命令が始めるヒアドキュメント (<<EOF・<<-EOF・<<"EOF" など。1 つの命令に複数書ける)
    line="${words[*]}"
    while [[ ${line} =~ \<\<(-?)[\"\']?([A-Za-z0-9_]+)[\"\']?(.*) ]]; do
      heredocs+=("${BASH_REMATCH[1]}${BASH_REMATCH[2]}")
      line=${BASH_REMATCH[3]}
    done
  done <"$1"
}

# Dockerfile の最終ステージを {dockerfile, target} の JSON 配列で出す。
# ステージと FROM の参照元は buildx の --call=targets で取り、buildx の出力に無い --from= の参照は from_refs で足す
# (参照はステージ名か番号。外部イメージの参照はどのステージにも当たらない)。
# 最終ステージが最後のステージだけなら、target を付けない (ビルドの既定と同じで、job 名も変わらない)
final_stages() {
  local dockerfile=$1 refs targets
  refs=$(from_refs "${dockerfile}" | tr '[:upper:]' '[:lower:]' | jq --raw-input . | jq --slurp --compact-output .)
  # 解析できない Dockerfile は target を付けずに入れ、ビルドのエラーをその image の scan-image に出す
  if ! targets=$(docker buildx build --call=targets,format=json --progress=quiet --file "${dockerfile}" "$(dirname "${dockerfile}")"); then
    echo "${dockerfile}: ステージを解析できないため、target を付けずにビルドする" >&2
    jq --null-input --compact-output --arg df "${dockerfile}" '[{dockerfile: $df}]'
    return
  fi
  jq --compact-output --arg df "${dockerfile}" --argjson refs "${refs}" '
    ([.targets[].base | ascii_downcase] + $refs) as $used
    | [.targets | to_entries[]
        | {id: (.key | tostring), name: (.value.name | if . then ascii_downcase else . end), default: (.value.default // false)}] as $stages
    # 名前でも番号でも参照されていないステージが最終ステージ。名前のないステージは --target で選べないので除く
    | [$stages[] | select(.default | not) | select(.name != null) | select(([.name, .id] - $used | length) == 2)] as $others
    # 最後のステージは、参照されていると読めても必ず入れる (Dockerfile がスキャンから丸ごと外れないようにする)
    | if ($others | length) == 0 then [{dockerfile: $df}]
      else [$others[] | {dockerfile: $df, target: .name}] + [{dockerfile: $df, target: ($stages[-1].name // "")}] end
  ' <<<"${targets}"
}

manifest=""
for f in .github/trivy-image.yml .github/trivy-image.yaml; do
  if [ -f "${f}" ]; then manifest="${f}"; break; fi
done

# 1. ビルドするイメージの一覧を作る（マニフェスト優先。無ければ Dockerfile を自動検出）
if [ -n "${manifest}" ]; then
  echo "${manifest} に列挙されたイメージをスキャンする"
  list=$(yq --output-format=json '.images // []' "${manifest}")
else
  echo "Dockerfile を自動検出し、最終ステージをすべてスキャンする"
  # Dockerfile.dockerignore（buildx の Dockerfile 別 ignore ファイル）は Dockerfile ではないので除外する
  list=$(
    find . -path ./.git -prune -o -type f \
      \( -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' \) \
      ! -name '*.dockerignore' -print \
      | sed 's|^\./||' | sort \
      | while IFS= read -r dockerfile; do final_stages "${dockerfile}"; done \
      | jq --slurp --compact-output 'add // []'
  )
fi

# 2. matrix で使う形に整える（label は job 名、suffix は cache scope / artifact 名に使う）
images=$(jq --compact-output '
  map(
    (.dockerfile // "") as $df | (.target // "") as $target |
    {
      dockerfile: $df,
      context: (.context // ($df | split("/") | .[:-1] | join("/") | if . == "" then "." else . end)),
      target: $target,
      build_args: (.["build-args"] // {} | to_entries | map("\(.key)=\(.value)") | join("\n")),
      label: ($df + (if $target == "" then "" else " (\($target))" end)),
      suffix: ($df + (if $target == "" then "" else "-\($target)" end) | gsub("[/.]"; "-"))
    }
  )' <<<"${list}")

# 3. マニフェストの記載ミスは、ビルドを待たずにここで落とす
while IFS= read -r f; do
  if [ -z "${f}" ] || [ ! -f "${f}" ]; then
    echo "::error::${manifest} の images[].dockerfile が未指定か、ファイルが存在しません: '${f}'"
    exit 1
  fi
done < <(jq --raw-output '.[].dockerfile' <<<"${images}")

echo "images=${images}" >> "$GITHUB_OUTPUT"
echo "スキャン対象: ${images}"
