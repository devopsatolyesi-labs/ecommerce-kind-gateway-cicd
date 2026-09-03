#!/usr/bin/env bash
# ==============================================================================
# Script: bootstrap-credentials.sh
# Description: Fully automated token generation for SonarQube & GitHub Secrets
# ==============================================================================
set -euo pipefail

SONAR_HOST="https://sonar.devopsatolyesi.com"
SONAR_USER="admin"
SONAR_PASS="${SONAR_PASS:-BilgincIT454}"
TOKEN_NAME="ecommerce-ci-pipeline-token"
REPO_NAME="devopsatolyesi-labs/ecommerce-kind-gateway-cicd"

log_info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
log_success() { printf '\033[1;32m[SUCCESS]\033[0m %s\n' "$*"; }
log_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

# 1. Revoke existing token if it exists (idempotency)
log_info "Ensuring idempotent token state in SonarQube..."
curl -s -u "${SONAR_USER}:${SONAR_PASS}" -X POST \
    "${SONAR_HOST}/api/user_tokens/revoke?name=${TOKEN_NAME}" >/dev/null 2>&1 || true

# 2. Generate new SonarQube analysis token
log_info "Generating dedicated SonarQube analysis token: ${TOKEN_NAME}..."
TOKEN_RESPONSE=$(curl -s -f -u "${SONAR_USER}:${SONAR_PASS}" -X POST \
    "${SONAR_HOST}/api/user_tokens/generate?name=${TOKEN_NAME}&type=GLOBAL_ANALYSIS_TOKEN")

SONAR_TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r '.token // empty')

if [[ -z "${SONAR_TOKEN}" ]]; then
    log_error "Failed to retrieve token from SonarQube API. Response: ${TOKEN_RESPONSE}"
    exit 1
fi

log_success "SonarQube Token generated successfully: ${SONAR_TOKEN:0:6}********"

# 3. Automated Injection into GitHub Secrets
log_info "Injecting SONAR_TOKEN into GitHub Secrets for repository: ${REPO_NAME}..."
echo "${SONAR_TOKEN}" | gh secret set SONAR_TOKEN -R "${REPO_NAME}"
gh variable set SONAR_HOST_URL --body "${SONAR_HOST}" -R "${REPO_NAME}"

# Also set for the other capstone repositories
for repo in "devopsatolyesi-labs/ecommerce-aws-elk-platform" "devopsatolyesi-labs/ecommerce-sre-slo-opentelemetry"; do
    log_info "Configuring secrets for ${repo}..."
    echo "${SONAR_TOKEN}" | gh secret set SONAR_TOKEN -R "${repo}" 2>/dev/null || true
    gh variable set SONAR_HOST_URL --body "${SONAR_HOST}" -R "${repo}" 2>/dev/null || true
done

log_success "All tokens and secrets successfully automated and synchronized across repositories!"
