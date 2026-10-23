#!/usr/bin/env bash
# Trivy で検知する severity と、渡す抑制ファイルを決めて、出力 severity / trivyignores に書く
set -euo pipefail

# --- severity: 組織の下限 MEDIUM,HIGH,CRITICAL に repo の trivy.yaml の指定を足す ---
# （CLI 引数は設定ファイルより優先されるため、repo 側から下限を弱めることはできない）
levels=(CRITICAL HIGH MEDIUM)
for cfg in trivy.yaml trivy.yml; do
  [ -f "${cfg}" ] || continue
  # severity は "LOW,UNKNOWN" 形式の文字列でも配列でも書ける。
  # 一度変数に受けるのは、yq / jq の失敗を set -e で拾うため
  raw=$(yq --output-format=json '.severity // []' "${cfg}" \
    | jq -r '[.] | flatten | map(tostring) | join(",") | ascii_upcase | gsub(" "; "")')
  IFS=, read -ra extra <<<"${raw}"
  for level in "${extra[@]}"; do
    case "${level}" in
      "") ;;
      UNKNOWN|LOW|MEDIUM|HIGH|CRITICAL) levels+=("${level}") ;;
      *) echo "::error file=${cfg}::severity に不正な値があります: ${level}"; exit 1 ;;
    esac
  done
  break
done
severity=$(printf '%s\n' "${levels[@]}" | sort -u | paste -sd, -)

# --- 抑制ファイル: Trivy が既定で読むのは .trivyignore だけなので、YAML 版は明示的に渡す ---
# （trivy-action は形式の違う 2 ファイルを併用できないため、両方あればエラーにする）
trivyignores=""
if [ -f .trivyignore.yaml ]; then
  if [ -f .trivyignore ]; then
    echo "::error file=.trivyignore.yaml::.trivyignore と .trivyignore.yaml は併用できません。どちらか一方にまとめてください"
    exit 1
  fi
  trivyignores=".trivyignore.yaml"
fi

echo "severity=${severity}" >> "$GITHUB_OUTPUT"
echo "trivyignores=${trivyignores}" >> "$GITHUB_OUTPUT"
echo "検知する severity: ${severity}"
echo "抑制ファイル: ${trivyignores:-.trivyignore（Trivy 既定）}"
