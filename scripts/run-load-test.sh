#!/usr/bin/env bash
# ==============================================================================
# Helper Script to Execute K6 Load Test against Traefik Gateway API
# ==============================================================================
set -euo pipefail

TARGET_URL="${1:-http://127.0.0.1:18081}"
HOST_HEADER="${2:-student100-app1.devopsatolyesi.com}"

echo "=================================================================="
echo "Starting K6 Load Test..."
echo "Target URL:  ${TARGET_URL}"
echo "Host Header: ${HOST_HEADER}"
echo "=================================================================="

# Run K6 via Docker container so no local installation is needed
docker run --rm -i \
  --network host \
  -e TARGET_URL="${TARGET_URL}" \
  -e HOST_HEADER="${HOST_HEADER}" \
  grafana/k6:0.53.0 run - < tests/k6-load-test.js

echo "Load test complete! Check Grafana for RPS and Latency metrics."
