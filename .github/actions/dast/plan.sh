#!/usr/bin/env bash
# repo の .github/dast.yml (環境変数 CONFIG) を検証し、ZAP の Automation Framework のプランを ${WORK_DIR}/plan.yaml に書く。
# scan.sh が使う compose のプロファイルと、起動を待つ URL は、出力 profile・wait_urls に書く。
#
# .github/dast.yml の書式:
#   compose_profile: dast        # 任意。docker compose で起動するプロファイル (プロファイルの無いサービスも起動する)
#   targets:                     # 必須。スキャンする origin
#     - url: http://localhost:3000
#       type: web                # 画面: クロール + 受動スキャン
#     - url: http://localhost:8000
#       type: api                # API: OpenAPI から全エンドポイントを能動スキャン
#       openapi: /openapi.json
#   ignores:                     # 任意。抑制 (変更には security チームの承認が要る)
#     - rule: "10055-5"          # ZAP のルール ID か alertRef
#       url: http://localhost:3000(/.*)?  # 抑制する URL の正規表現。URL 全体に一致させる (末尾の / が無い URL もある)
#       reason: 抑制する理由
set -euo pipefail

settings=$(yq --output-format=json '.' "${CONFIG}")
mkdir -p "${WORK_DIR}"

# 1. 設定の誤りは、ビルドを待たずにここで落とす。
#    url は localhost の origin だけを許す。PR からデプロイ済みの環境を攻撃させないための設定ミスの防止で、
#    セキュリティの境界ではない (PR は compose.yaml も書き換えられる)
errors=$(jq --raw-output '
  def str: type == "string" and length > 0;
  def origin: str and test("\\Ahttp://(localhost|127\\.0\\.0\\.1)(:[0-9]{1,5})?/?\\z");
  def path: str and test("\\A/[A-Za-z0-9._~/-]*\\z");
  [
    (if has("compose_profile") and (.compose_profile | str and test("\\A[A-Za-z0-9_.-]+\\z") | not)
      then "compose_profile は英数字・_ . - で書いてください" else empty end),
    (if (.targets | type) != "array" or (.targets | length) == 0 then "targets を 1 つ以上書いてください" else empty end),
    ((.targets // [])[] as $t | ($t | tojson) as $j |
      (if ($t.url | origin | not) then "targets の url は http://localhost か http://127.0.0.1 の origin にしてください: \($j)" else empty end),
      (if ($t.type | IN("web", "api") | not) then "targets の type は web か api にしてください: \($j)" else empty end),
      (if $t.type == "api" and ($t.openapi | path | not) then "type: api には openapi (/ で始まるパス) を書いてください: \($j)" else empty end)),
    ((.ignores // [])[] as $i | ($i | tojson) as $j |
      (if ($i.rule | tostring | test("\\A[0-9]+(-[0-9]+)?\\z") | not) then "ignores の rule は ZAP のルール ID か alertRef にしてください: \($j)" else empty end),
      (if ($i.url | str | not) or ($i.reason | str | not) then "ignores には url と reason を書いてください: \($j)" else empty end))
  ] | .[]
' <<<"${settings}")
if [ -n "${errors}" ]; then
  while IFS= read -r error; do echo "::error file=${CONFIG}::${error}"; done <<<"${errors}"
  exit 1
fi

# 2. プランを作る。ジョブは書いた順に動く。alertFilter は登録した後に出たアラートにしか効かないため最初に置く。
#    context を省くと最初の context が使われるため、各ジョブに明示する
jq --compact-output '
  [.targets[] | (.url | rtrimstr("/")) as $url | . + {
    url: $url,
    context: ($url | sub("\\Ahttp://"; "") | gsub("[.:]"; "-")),
    openapi_url: (if .type == "api" then $url + .openapi else null end)
  }] as $targets |
  def report($template; $file; $confidences):
    {type: "report", parameters: {template: $template, reportDir: "/zap/wrk/report", reportFile: $file}}
    + (if $confidences then {confidences: $confidences} else {} end);
  {
    env: {
      contexts: [$targets[] | {name: .context, urls: [.url], includePaths: ["^\\Q\(.url)\\E(/.*)?$"]}],
      parameters: {failOnError: true, failOnWarning: false, progressToStdout: true}
    },
    jobs: (
      [if (.ignores // []) == [] then empty else
        {type: "alertFilter", alertFilters: [.ignores[] | {ruleId: (.rule | tostring), newRisk: "False Positive", url, urlRegex: true}]}
      end]
      + [$targets[] | select(.type == "api") | {type: "openapi", parameters: {context, apiUrl: .openapi_url, targetUrl: .url}}]
      + [$targets[] | select(.type == "web") | {type: "spider", parameters: {context, url, maxDuration: 1}}]
      + [{type: "passiveScan-wait", parameters: {maxDuration: 5}}]
      + [$targets[] | select(.type == "api") | {type: "activeScan", parameters: {context, maxScanDurationInMins: 8}}]
      + [{type: "passiveScan-wait", parameters: {maxDuration: 5}}]
      + [
        report("traditional-html"; "zap-report.html"; null),
        report("traditional-json"; "zap-report.json"; null),
        # log と job summary に出す。抑制したアラート (False Positive) は載せない
        report("traditional-md"; "zap-report.md"; ["high", "medium", "low"])
      ]
      # AF は警告だけでも終了コード 2 になるため、警告では落とさない。
      # Medium 以上かどうかは scan.sh が JSON レポートで判定する (errorLevel は、一部の URL だけ抑制したアラートを見逃す)
      + [{type: "exitStatus", parameters: {warnExitValue: 0}}]
    )
  }
' <<<"${settings}" | yq --prettyPrint --input-format=json > "${WORK_DIR}/plan.yaml"
echo "ZAP のプラン:"
cat "${WORK_DIR}/plan.yaml"

# 3. scan.sh に渡す。画面は origin、API は OpenAPI の URL が応答するまで待つ (API の origin は 404 を返し得る)
echo "profile=$(jq --raw-output '.compose_profile // ""' <<<"${settings}")" >> "${GITHUB_OUTPUT}"
echo "wait_urls=$(jq --compact-output '[.targets[] | (.url | rtrimstr("/")) + (.openapi // "/")]' <<<"${settings}")" >> "${GITHUB_OUTPUT}"
