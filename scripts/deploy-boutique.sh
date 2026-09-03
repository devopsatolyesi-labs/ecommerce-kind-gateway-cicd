#!/usr/bin/env bash
# ==============================================================================
# Script: deploy-boutique.sh
# Description: Deploys Google Online Boutique with Traefik Gateway API Route
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

log_info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
log_success() { printf '\033[1;32m[SUCCESS]\033[0m %s\n' "$*"; }

if ! kubectl get gateway traefik-gateway -n traefik &>/dev/null; then
    log_info "Ensuring Traefik Gateway API Controller is installed..."
    "${SCRIPT_DIR}/setup-traefik-gateway.sh"
else
    log_info "Traefik Gateway already running, proceeding to app deployment..."
fi

log_info "Deploying Google Online Boutique microservices..."
kubectl apply -f "${ROOT_DIR}/kubernetes-manifests/"

log_info "Applying Traefik Gateway API HTTPRoute for Frontend..."
kubectl apply -f "${ROOT_DIR}/gateway-api/03-httproute.yaml"

log_info "Waiting for Online Boutique microservices rollout..."
kubectl rollout status deployment/frontend --timeout=120s
kubectl rollout status deployment/checkoutservice --timeout=120s
kubectl rollout status deployment/productcatalogservice --timeout=120s

log_success "Online Boutique successfully deployed with Traefik Gateway API!"
kubectl get pods,httproutes -l app=frontend
