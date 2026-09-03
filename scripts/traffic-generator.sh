#!/usr/bin/env bash
# ==============================================================================
# Background Traffic Generator for Online Boutique Gateway API
# Generates realistic HTTP traffic to demonstrate live Grafana metrics
# ==============================================================================

TARGET_URL="${1:-http://127.0.0.1:18081}"

echo "Starting traffic generator against ${TARGET_URL}..."

while true; do
  # Home page request (200 OK)
  curl -s -o /dev/null -H "Host: student100-app1.devopsatolyesi.com" "${TARGET_URL}/" || true
  sleep 0.2

  # Product details requests
  curl -s -o /dev/null -H "Host: student100-app1.devopsatolyesi.com" "${TARGET_URL}/product/OLJCESPC7Z" || true
  sleep 0.3

  # Cart requests
  curl -s -o /dev/null -H "Host: student100-app1.devopsatolyesi.com" "${TARGET_URL}/cart" || true
  sleep 0.2

  # Intentional 404 to demonstrate error tracking
  if (( RANDOM % 5 == 0 )); then
    curl -s -o /dev/null -H "Host: student100-app1.devopsatolyesi.com" "${TARGET_URL}/non-existent-product" || true
  fi

  sleep 0.5
done
