#!/usr/bin/env bash
set -euo pipefail

API_BASE="${AGFS_API_BASE:-http://localhost:8080/api/v1}"
QUERY="${1:-llm agents in 2025}"
MAX_RESULTS="${AGFS_MAX_RESULTS:-2}"
SUMMARY_FORMAT="${AGFS_SUMMARY_FORMAT:-bullet list}"
POLL_ATTEMPTS="${AGFS_POLL_ATTEMPTS:-30}"
POLL_DELAY="${AGFS_POLL_DELAY:-2}"
PRINT_SEARCH="${AGFS_PRINT_SEARCH:-1}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd curl
require_cmd jq

echo "[1/4] Sending query to simpcurlfs (/web/request)..."
REQUEST_JSON="$(jq -n --arg q "$QUERY" --argjson max "$MAX_RESULTS" '{query:$q, max_results:$max}')"
curl -sS -X PUT -H "Content-Type: application/json" \
  --data "${REQUEST_JSON}" \
  "${API_BASE}/files?path=/web/request" >/dev/null

poll_file() {
  local path="$1"
  local attempts="$2"
  local delay="$3"
  for ((i=1; i<=attempts; i++)); do
    if CONTENT="$(curl -fsS "${API_BASE}/files?path=${path}" 2>/dev/null)"; then
      if [[ -n "${CONTENT}" ]]; then
        echo "${CONTENT}"
        return 0
      fi
    fi
    sleep "${delay}"
  done
  echo "Timed out waiting for ${path}" >&2
  return 1
}

echo "[2/4] Waiting for /web/response.txt..."
WEB_RESPONSE="$(poll_file "/web/response.txt" "${POLL_ATTEMPTS}" "${POLL_DELAY}")"

echo "[3/4] Sending text to summaryfs (/summary/request)..."
SUMMARY_PAYLOAD="$(jq -n --arg text "${WEB_RESPONSE}" --arg format "${SUMMARY_FORMAT}" '{text:$text, format:$format}')"
curl -sS -X PUT -H "Content-Type: application/json" \
  --data "${SUMMARY_PAYLOAD}" \
  "${API_BASE}/files?path=/summary/request" >/dev/null

echo "[4/4] Waiting for /summary/response.txt..."
SUMMARY_RESPONSE="$(poll_file "/summary/response.txt" "${POLL_ATTEMPTS}" "${POLL_DELAY}")"

if [[ "${PRINT_SEARCH}" == "1" || "${PRINT_SEARCH}" == "true" ]]; then
  echo ""
  echo "====== SimpcurlFS Result ======"
  printf "%s\n" "${WEB_RESPONSE}"
  echo ""
fi
echo "====== SummaryFS Result ======"
printf "%s\n" "${SUMMARY_RESPONSE}"
