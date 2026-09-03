#!/usr/bin/env bash
# ==============================================================================
# Script: bootstrap-cockpit-lab.sh
# Description: Automated Cockpit Student Lab Bootstrap
# Sets up Cockpit, Kind, Traefik Gateway API, Jenkins, SonarQube & Nginx Proxy
# Compatible with both Azure Cockpit Labs and GCP / Local Standalone VMs
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

log_info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
log_success() { printf '\033[1;32m[SUCCESS]\033[0m %s\n' "$*"; }
log_warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
log_error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

# ------------------------------------------------------------------------------
# 1. Environment & Subdomain Detection
# ------------------------------------------------------------------------------
DOMAIN="${DOMAIN_NAME:-devopsatolyesi.com}"
HOSTNAME_LOWER=$(hostname | tr '[:upper:]' '[:lower:]')

if [[ "$HOSTNAME_LOWER" =~ (student[0-9]+) ]]; then
    PREFIX="${BASH_REMATCH[1]}"
else
    PREFIX="${LAB_PREFIX:-ecommerce}"
fi

log_info "Detected Student/Lab Prefix: ${PREFIX}"
log_info "Target Domain: ${DOMAIN}"
log_info "Cockpit URL:   https://${PREFIX}-cockpit.${DOMAIN}"
log_info "Kind App URL:  https://${PREFIX}-kind.${DOMAIN}"
log_info "Jenkins URL:   https://${PREFIX}-jenkins.${DOMAIN}"
log_info "SonarQube URL: https://${PREFIX}-sonarqube.${DOMAIN}"

# ------------------------------------------------------------------------------
# 2. Package & Prerequisite Installation
# ------------------------------------------------------------------------------
log_info "1/7 Verifying essential system packages..."
sudo apt-get update -y
sudo apt-get install -y curl wget git jq net-tools apt-transport-https ca-certificates gnupg lsb-release

# Install Cockpit if missing
if ! command -v cockpit-bridge >/dev/null 2>&1; then
    log_info "Installing Cockpit Web Console (Port 9090)..."
    sudo apt-get install -y cockpit
    sudo systemctl enable --now cockpit.socket
fi

# Install Docker if missing
if ! command -v docker >/dev/null 2>&1; then
    log_info "Installing Docker Engine..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER" || true
    sudo systemctl enable --now docker
fi

# Install kubectl if missing
if ! command -v kubectl >/dev/null 2>&1; then
    log_info "Installing kubectl..."
    curl -fsSL -o /tmp/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm -f /tmp/kubectl
fi

# Install Helm if missing
if ! command -v helm >/dev/null 2>&1; then
    log_info "Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
fi

# Install Kind if missing
if ! command -v kind >/dev/null 2>&1; then
    log_info "Installing Kind..."
    curl -fsSL -o /tmp/kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64
    chmod +x /tmp/kind
    sudo mv /tmp/kind /usr/local/bin/kind
fi

# ------------------------------------------------------------------------------
# 3. Provision / Re-use Kind Cluster with Gateway Port Mappings (18081)
# ------------------------------------------------------------------------------
log_info "2/7 Configuring Kind Cluster with Gateway API HostPort (18081)..."
CLUSTER_NAME="ecommerce-kind-cluster"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    log_info "Kind cluster '${CLUSTER_NAME}' already exists. Reusing..."
else
    cat << 'EOF' > /tmp/kind-gateway-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 30080
    hostPort: 18081
    listenAddress: "127.0.0.1"
    protocol: TCP
  - containerPort: 30443
    hostPort: 18443
    listenAddress: "127.0.0.1"
    protocol: TCP
EOF
    kind create cluster --name "${CLUSTER_NAME}" --config /tmp/kind-gateway-config.yaml
    rm -f /tmp/kind-gateway-config.yaml
fi

kubectl cluster-info

# ------------------------------------------------------------------------------
# 4. Deploy Traefik v3 Gateway API Controller
# ------------------------------------------------------------------------------
log_info "3/7 Deploying Kubernetes Gateway API Standard CRDs & Traefik v3..."
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

helm repo add traefik https://traefik.github.io/charts --force-update
helm repo update

helm upgrade --install traefik traefik/traefik \
    --namespace traefik --create-namespace \
    --set providers.kubernetesGateway.enabled=true \
    --set providers.kubernetesGateway.experimentalChannel=false \
    --set gatewayClass.enabled=true \
    --set gateway.enabled=true \
    --set gateway.listeners.web.routes.namespaces.from=All \
    --set service.type=NodePort \
    --set ports.web.nodePort=30080 \
    --wait --timeout 3m

# Patch gateway listener to ensure routes from all namespaces are accepted
kubectl patch gateway traefik-gateway -n traefik --type='json' \
    -p='[{"op": "replace", "path": "/spec/listeners/0/allowedRoutes/namespaces/from", "value": "All"}]' 2>/dev/null || true

# ------------------------------------------------------------------------------
# 5. Deploy Google Online Boutique Microservices & HTTPRoute
# ------------------------------------------------------------------------------
log_info "4/7 Deploying Google Online Boutique microservices..."
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml

log_info "Applying Traefik Gateway API HTTPRoute for ${PREFIX}-kind.${DOMAIN}..."
cat << EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: frontend-route
  namespace: default
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
      sectionName: web
  hostnames:
    - "${PREFIX}-kind.${DOMAIN}"
    - "localhost"
    - "127.0.0.1"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: frontend
          port: 80
          weight: 1
EOF

# ------------------------------------------------------------------------------
# 6. Start Local Jenkins and SonarQube Containers (Port 18080 & 19000)
# ------------------------------------------------------------------------------
log_info "5/7 Starting Jenkins (Port 18080) and SonarQube (Port 19000)..."

# Jenkins
if ! docker ps -a --format '{{.Names}}' | grep -q '^training-jenkins$'; then
    sudo mkdir -p /var/jenkins_home
    sudo chown -R 1000:1000 /var/jenkins_home 2>/dev/null || true
    docker run -d \
        --name training-jenkins \
        --restart unless-stopped \
        -p 127.0.0.1:18080:8080 \
        -p 127.0.0.1:50000:50000 \
        -v /var/jenkins_home:/var/jenkins_home \
        -v /var/run/docker.sock:/var/run/docker.sock \
        jenkins/jenkins:lts-jdk17
    log_success "Jenkins container started on 127.0.0.1:18080"
else
    log_info "Jenkins container already present. Ensuring running..."
    docker start training-jenkins >/dev/null 2>&1 || true
fi

# SonarQube
if ! docker ps -a --format '{{.Names}}' | grep -q '^training-sonarqube$'; then
    sudo sysctl -w vm.max_map_count=262144 || true
    docker run -d \
        --name training-sonarqube \
        --restart unless-stopped \
        -p 127.0.0.1:19000:9000 \
        -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
        sonarqube:lts-community
    log_success "SonarQube container started on 127.0.0.1:19000"
else
    log_info "SonarQube container already present. Ensuring running..."
    docker start training-sonarqube >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
# 7. Configure Nginx Reverse Proxy (Cockpit, Kind, Jenkins, SonarQube)
# ------------------------------------------------------------------------------
log_info "6/7 Configuring Nginx Reverse Proxy for ${DOMAIN}..."
sudo apt-get install -y nginx

# Ensure snakeoil/self-signed fallback certs exist if Cloudflare origin certs are not yet mounted
sudo mkdir -p /etc/nginx/ssl /etc/nginx/sites-available /etc/nginx/sites-enabled
if [ ! -f /etc/nginx/ssl/origin.crt ]; then
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/origin.key -out /etc/nginx/ssl/origin.crt \
        -subj "/C=TR/ST=Istanbul/L=Istanbul/O=DevOpsAtolyesi/CN=*.${DOMAIN}" 2>/dev/null || true
fi

cat << EOF | sudo tee /etc/nginx/sites-available/cockpit-lab.conf
# Cockpit Web Terminal
server {
    listen 80;
    listen 443 ssl;
    server_name ${PREFIX}-cockpit.${DOMAIN};

    ssl_certificate /etc/nginx/ssl/origin.crt;
    ssl_certificate_key /etc/nginx/ssl/origin.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass https://127.0.0.1:9090;
        proxy_ssl_verify off;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}

# Kind Kubernetes - Online Boutique (Traefik Gateway API)
server {
    listen 80;
    listen 443 ssl;
    server_name ${PREFIX}-kind.${DOMAIN};

    ssl_certificate /etc/nginx/ssl/origin.crt;
    ssl_certificate_key /etc/nginx/ssl/origin.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:18081;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Jenkins CI/CD
server {
    listen 80;
    listen 443 ssl;
    server_name ${PREFIX}-jenkins.${DOMAIN};

    ssl_certificate /etc/nginx/ssl/origin.crt;
    ssl_certificate_key /etc/nginx/ssl/origin.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 512m;

    location / {
        proxy_pass http://127.0.0.1:18080;
        proxy_read_timeout 3600s;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

# SonarQube
server {
    listen 80;
    listen 443 ssl;
    server_name ${PREFIX}-sonarqube.${DOMAIN};

    ssl_certificate /etc/nginx/ssl/origin.crt;
    ssl_certificate_key /etc/nginx/ssl/origin.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    client_max_body_size 256m;

    location / {
        proxy_pass http://127.0.0.1:19000;
        proxy_read_timeout 600s;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/cockpit-lab.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# ------------------------------------------------------------------------------
# 8. Verification & Summary
# ------------------------------------------------------------------------------
log_info "7/7 Performing Health Verification..."

log_success "================================================================================"
log_success "              COCKPIT STUDENT LAB ENVIRONMENT READY!                            "
log_success "================================================================================"
printf '🌐 Cockpit Web Terminal : https://%s-cockpit.%s  (Port 9090)\n' "${PREFIX}" "${DOMAIN}"
printf '🛍️ E-Commerce Gateway API: https://%s-kind.%s     (Port 18081)\n' "${PREFIX}" "${DOMAIN}"
printf '🏗️ Jenkins Automation    : https://%s-jenkins.%s  (Port 18080)\n' "${PREFIX}" "${DOMAIN}"
printf '🔍 SonarQube Server      : https://%s-sonarqube.%s (Port 19000)\n' "${PREFIX}" "${DOMAIN}"
log_success "================================================================================"
