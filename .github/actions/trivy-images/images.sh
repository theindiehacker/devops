#!/usr/bin/env bash
# trivy.yml の scan-image でビルドしてスキャンするイメージを決め、matrix に渡す JSON 配列を出力 images に書く。
#   - .github/trivy-image.yml があれば、列挙された image だけをビルドする
#   - 無ければ Dockerfile / Dockerfile.* / *.Dockerfile を自動検出し、置き場所を build context に、
#     最終ステージ (ほかのステージから FROM・COPY --from・RUN --mount の from= で使われないステージ) をすべて target にする
set -euo pipefail

# Dockerfile の最終ステージを {dockerfile, target} の JSON 配列で出す。
# ステージと FROM の参照元は buildx の --call=targets で取る。COPY --from・RUN --mount の from= の参照は buildx の出力に無いため、
# Dockerfile から拾って足す (参照はステージ名か番号。外部イメージの参照はどのステージにも当たらない)。
# 最終ステージが最後のステージ 1 つだけなら、target を付けない (ビルドの既定と同じで、job 名も変わらない)
final_stages() {
  local dockerfile=$1 refs targets
  refs=$({ grep -v -E '^[[:space:]]*#' "${dockerfile}" | grep -o -i -E '(--from|[[:space:],]from)=[A-Za-z0-9_.-]+' || true; } \
    | sed 's/.*=//' | tr '[:upper:]' '[:lower:]' | jq --raw-input . | jq --slurp --compact-output .)
  # 解析できない Dockerfile は target を付けずに入れ、ビルドのエラーをその image の scan-image に出す
  if ! targets=$(docker buildx build --call=targets,format=json --progress=quiet --file "${dockerfile}" "$(dirname "${dockerfile}")"); then
    echo "${dockerfile}: ステージを解析できないため、target を付けずにビルドする" >&2
    jq --null-input --compact-output --arg df "${dockerfile}" '[{dockerfile: $df}]'
    return
  fi
  jq --compact-output --arg df "${dockerfile}" --argjson refs "${refs}" '
    ([.targets[].base | ascii_downcase] + $refs) as $used
    | [.targets | to_entries[]
        | {id: (.key | tostring), name: (.value.name | if . then ascii_downcase else . end), default: (.value.default // false)}
        # 名前でも番号でも参照されていないステージが最終ステージ
        | select(([.name, .id] - $used | length) == 2)] as $leaves
    | if ($leaves | length) == 1 and $leaves[0].default then [{dockerfile: $df}]
      # 名前のないステージは --target で選べない。最後のステージだけは target なしでビルドできる
      else [$leaves[] | select(.name != null or .default) | {dockerfile: $df, target: (.name // "")}] end
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
