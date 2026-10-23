#!/usr/bin/env bash
# bun を SHA-256 を検証して /usr/local/bin に導入する
set -euo pipefail

archive="${RUNNER_TEMP}/bun-linux-x64.zip"
curl -sSfL -o "${archive}" "https://github.com/oven-sh/bun/releases/download/${VERSION}/${archive##*/}"

# SHA-256 検証（改ざん・破損を検知）
echo "${SHA256}  ${archive}" | sha256sum -c -

sudo unzip -o -j "${archive}" "bun-linux-x64/bun" -d /usr/local/bin
sudo chmod +x /usr/local/bin/bun
bun --version
