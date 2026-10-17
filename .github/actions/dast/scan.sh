#!/usr/bin/env bash
# PR のコードからアプリを docker compose で起動し、plan.sh が作ったプラン (${WORK_DIR}/plan.yaml) で ZAP を実行する。
# 終了コードは ZAP のもの (Medium 以上の検知やプランのエラーで 1)。compose のプロファイルは COMPOSE_PROFILES で受け取る
set -euo pipefail

# 1. アプリを起動する。待ち受けを始めるまでは接続を切られるので、--retry-all-errors で待つ
docker compose up --detach --build
mapfile -t urls < <(jq --raw-output '.[]' <<<"${WAIT_URLS}")
for url in "${urls[@]}"; do
  echo "起動を待つ: ${url}"
  if ! curl --fail --silent --show-error --output /dev/null \
    --retry 60 --retry-delay 2 --retry-all-errors --max-time 5 "${url}"; then
    echo "::error::${url} が応答しません (type: api は openapi の URL が 200 を返す必要があります)"
    exit 1
  fi
done

# 2. ZAP を実行する。コンテナは uid 1000 の zap ユーザーで動くため、作業ディレクトリを書き込めるようにする (公式 action と同じ)。
#    ZAP はレポートの置き場所を作らないので、先に作る。-silent: 更新の確認など、スキャン以外の通信をさせない
mkdir -p "${WORK_DIR}/report"
chmod a+w "${WORK_DIR}" "${WORK_DIR}/report"
rc=0
timeout 13m docker run --rm --network host --volume "${WORK_DIR}:/zap/wrk/:rw" "${ZAP_IMAGE}" \
  zap.sh -cmd -silent -autorun /zap/wrk/plan.yaml || rc=$?
if [ "${rc}" -eq 124 ]; then
  echo "::error::ZAP のスキャンが 13 分で終わりませんでした"
fi

# 3. 結果を log と job summary に出す (job summary は 1 MiB まで)
report="${WORK_DIR}/report/zap-report.md"
if [ -f "${report}" ]; then
  cat "${report}"
  head --bytes 1000000 "${report}" >> "${GITHUB_STEP_SUMMARY}"
fi

# 4. Medium (riskcode 2) 以上で失敗する。抑制したアラートは confidence が 0 (False Positive) になる
if [ "${rc}" -eq 0 ]; then
  count=$(jq '[.site[].alerts[] | select((.riskcode | tonumber) >= 2 and .confidence != "0")] | length' "${WORK_DIR}/report/zap-report.json")
  if [ "${count}" -gt 0 ]; then
    echo "::error::Medium 以上のアラートが ${count} 種類あります。直すか、.github/dast.yml の ignores に理由付きで足してください"
    rc=1
  fi
fi
exit "${rc}"
