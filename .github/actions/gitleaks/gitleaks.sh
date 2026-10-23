#!/usr/bin/env bash
# gitleaks を導入し、PR のコミット範囲 (LOG_OPTS) をスキャンする
set -euo pipefail

archive="${RUNNER_TEMP}/gitleaks_${VERSION#v}_linux_x64.tar.gz"
curl -sSfL -o "${archive}" "https://github.com/gitleaks/gitleaks/releases/download/${VERSION}/${archive##*/}"

# SHA-256 検証（改ざん・破損を検知）
echo "${SHA256}  ${archive}" | sha256sum -c -

sudo tar -xz -C /usr/local/bin -f "${archive}" gitleaks
gitleaks version

# --ignore-gitleaks-allow: インライン allow コメントを無効化（抑制は承認必須の .gitleaksignore に限定する）
# --max-archive-depth: zip / tar.gz などの圧縮ファイルを展開して中身も検査する（入れ子は 5 階層まで）
gitleaks git . --redact --verbose --exit-code 1 --ignore-gitleaks-allow --max-archive-depth 5 --log-opts="${LOG_OPTS}"
