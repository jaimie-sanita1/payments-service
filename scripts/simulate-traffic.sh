#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-http://localhost/payments}"

VERBOSE=0
SLOW=0
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
    -s|--slow) SLOW=1 ;;
  esac
done

BAD_REQUEST_RATE="${BAD_REQUEST_RATE:-12}"
CANCEL_RATE="${CANCEL_RATE:-35}"
READS_RATE="${READS_RATE:-70}"

rand_amount() {
  local a=(500 1000 1500 2500 5000 7500 10000)
  echo "${a[$((RANDOM % ${#a[@]}))]}"
}
rand_currency() {
  local c=(USD EUR GBP CAD)
  echo "${c[$((RANDOM % ${#c[@]}))]}"
}
idem_key() { echo "demo-$(date +%s)-$RANDOM$RANDOM"; }
maybe_bad() { [[ $((RANDOM % 100)) -lt "${BAD_REQUEST_RATE}" ]]; }
chance() { [[ $((RANDOM % 100)) -lt "$1" ]]; }

request() {
  local method="$1" path="$2" payload="${3:-}" key="${4:-}"
  [[ "${SLOW}" == "1" ]] && sleep 1

  local out status
  out="$(curl -sS -X "${method}" "${BASE}${path}" \
    -H 'content-type: application/json' \
    ${key:+-H "X-Idempotency-Key: ${key}"} \
    ${payload:+-d "${payload}"} \
    -w $'\n__STATUS__:%{http_code}' || true)"
  status="$(echo "${out}" | sed -nE 's/^__STATUS__:(.*)$/\1/p' | tail -n 1)"
  [[ -z "${status}" ]] && status="000"

  if [[ "${status}" =~ ^2 ]]; then
    printf "✓ %s %s (%s)\n" "${method}" "${path}" "${status}" >&2
  else
    printf "✗ %s %s (%s)\n" "${method}" "${path}" "${status}" >&2
  fi
  [[ "${VERBOSE}" == "1" && -n "${payload}" ]] && echo "    payload: ${payload}" >&2
  echo "${out}" | sed '/^__STATUS__:/,$d'
}

extract_id() {
  echo "$1" | sed -nE 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1
}

echo "🚦 Payments traffic generator"
echo "Base: ${BASE}"
echo
trap 'echo; echo "Stopping."; exit 0' INT

while true; do
  amt="$(rand_amount)"
  cur="$(rand_currency)"
  good="{\"amount\":${amt},\"currency\":\"${cur}\",\"method\":{\"type\":\"card\",\"cardToken\":\"tok_visa_4242\"}}"
  bad="{\"currency\":\"${cur}\"}"

  body="${good}"
  maybe_bad && body="${bad}"
  resp="$(request POST /v1/payments "${body}" "$(idem_key)")"
  pay_id="$(extract_id "${resp}")"

  # Missing X-Idempotency-Key -> 400
  maybe_bad && request POST /v1/payments "${good}" >/dev/null

  if chance "${READS_RATE}"; then
    [[ -n "${pay_id}" ]] && request GET "/v1/payments/${pay_id}" >/dev/null
    request GET /v1/payments/pay_1001 >/dev/null
    maybe_bad && request GET /v1/payments/not-a-real-id >/dev/null
  fi

  if chance "${CANCEL_RATE}"; then
    [[ -n "${pay_id}" ]] && request POST "/v1/payments/${pay_id}/cancel" >/dev/null
    # Settled payment -> 409
    maybe_bad && request POST /v1/payments/pay_1002/cancel >/dev/null
  fi
done
