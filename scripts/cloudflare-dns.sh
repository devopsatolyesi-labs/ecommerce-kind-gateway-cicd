#!/usr/bin/env bash
# ==============================================================================
# Script: cloudflare-dns.sh
# Description: Synchronize student DNS A-records on Cloudflare
# ==============================================================================
set -euo pipefail

log() { printf '\033[1;34m[DNS]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

ACTION="${1:-apply}"
STUDENT="${2:-student100}"
PUBLIC_IP="${3:-34.79.10.78}"
DOMAIN="${DOMAIN_NAME:-devopsatolyesi.com}"
PROXIED="${CLOUDFLARE_PROXIED:-true}"

: "${CLOUDFLARE_API_TOKEN:?Set CLOUDFLARE_API_TOKEN}"
: "${CLOUDFLARE_ZONE_ID:?Set CLOUDFLARE_ZONE_ID}"

api="https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records"
auth=(-H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H 'Content-Type: application/json')

zone_info=$(curl -fsS "${auth[@]}" "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}")
zone_name=$(jq -r '.result.name // empty' <<<"$zone_info")
log "Connected to Cloudflare Zone: ${zone_name} (ID: ${CLOUDFLARE_ZONE_ID})"

services=(
  cockpit
  jenkins
  sonarqube
  app1
  k8s-app1
  kind
)

lookup_id() {
  local fqdn="$1"
  curl -fsS "${auth[@]}" --get "$api" \
    --data-urlencode "type=A" \
    --data-urlencode "name=${fqdn}" \
    | jq -r '.result[0].id // empty'
}

upsert_record() {
  local fqdn="$1" ip="$2" record_id payload response
  record_id="$(lookup_id "$fqdn")"
  payload="$(jq -n \
    --arg name "$fqdn" \
    --arg content "$ip" \
    --argjson proxied "$PROXIED" \
    '{type:"A",name:$name,content:$content,ttl:1,proxied:$proxied}')"

  if [[ -n "$record_id" ]]; then
    response="$(curl -fsS -X PUT "${auth[@]}" "${api}/${record_id}" --data "$payload")"
  else
    response="$(curl -fsS -X POST "${auth[@]}" "$api" --data "$payload")"
  fi
  jq -e '.success == true' >/dev/null <<<"$response" \
    || die "Cloudflare rejected record ${fqdn}: ${response}"
  log "DNS ready: ${fqdn} -> ${ip} (proxied=${PROXIED})"
}

delete_record() {
  local fqdn="$1" record_id response
  record_id="$(lookup_id "$fqdn")"
  if [[ -z "$record_id" ]]; then
    log "DNS already absent: ${fqdn}"
    return
  fi
  response="$(curl -fsS -X DELETE "${auth[@]}" "${api}/${record_id}")"
  jq -e '.success == true' >/dev/null <<<"$response" \
    || die "Cloudflare could not delete ${fqdn}: ${response}"
  log "DNS deleted: ${fqdn}"
}

for service in "${services[@]}"; do
  fqdn="${STUDENT}-${service}.${DOMAIN}"
  case "$ACTION" in
    apply) upsert_record "$fqdn" "$PUBLIC_IP" ;;
    delete) delete_record "$fqdn" ;;
  esac
done

log "DNS synchronization completed successfully for ${STUDENT}!"
