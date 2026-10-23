#!/usr/bin/env bash
# ghalint を導入し、permissions 未設定・アクションの SHA 未固定など、構文ではなくセキュリティ観点のポリシー違反を検出する
set -euo pipefail

archive="${RUNNER_TEMP}/ghalint_${VERSION#v}_linux_amd64.tar.gz"
curl -sSfL -o "${archive}" "https://github.com/suzuki-shunsuke/ghalint/releases/download/${VERSION}/${archive##*/}"

# SHA-256 検証（改ざん・破損を検知）
echo "${SHA256}  ${archive}" | sha256sum -c -

sudo tar -xz -C /usr/local/bin -f "${archive}" ghalint
ghalint version

# ghalint run は個別ファイル指定ができないため、.github/workflows/ 全体が対象になる
ghalint run
