#!/usr/bin/env bash
# ==============================================================================
# Script: setup-traefik-gateway.sh
# Description: Installs Kubernetes Gateway API CRDs & Traefik v3 Controller
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

log_info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
log_success() { printf '\033[1;32m[SUCCESS]\033[0m %s\n' "$*"; }
log_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

# 1. Verify kubectl connectivity
if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "Cannot connect to Kubernetes cluster. Verify KUBECONFIG."
    exit 1
fi

log_info "Connected to Kubernetes cluster: $(kubectl config current-context)"

# 2. Install Official Kubernetes Gateway API Standard CRDs (v1.5.1)
log_info "Applying Kubernetes Gateway API Standard CRDs (v1.5.1)..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

# 3. Add and update Traefik Helm Repository
log_info "Configuring Traefik Helm repository..."
helm repo add traefik https://traefik.github.io/charts --force-update
helm repo update

# 4. Deploy Traefik v3 with Gateway API Provider
log_info "Deploying Traefik v3 Gateway Controller..."
helm upgrade --install traefik traefik/traefik \
    --namespace traefik \
    --create-namespace \
    --values "${ROOT_DIR}/traefik/traefik-values.yaml" \
    --wait --timeout 5m

# 5. Apply GatewayClass & Gateway Definition
log_info "Applying GatewayClass and Gateway resources..."
kubectl apply -f "${ROOT_DIR}/gateway-api/01-gateway-class.yaml"
kubectl apply -f "${ROOT_DIR}/gateway-api/02-gateway.yaml"

log_success "Traefik v3 Gateway API Controller successfully deployed and ready!"
kubectl get gatewayclasses,gateways -A
