#!/bin/bash
# =============================================================================
# Shared configuration for Infisical installation scripts
# Source this file: source ./install.core.sh
# =============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="${NAMESPACE:-infisical}"
DOMAIN="${DOMAIN:-infisical.noizu.com}"
POSTGRES_VERSION="${POSTGRES_VERSION:-LATEST}"
REDIS_VERSION="${REDIS_VERSION:-24.0.8}"
INFISICAL_VERSION="${INFISICAL_VERSION:-v0.154.5}"

# Service names
POSTGRES_NAME="sec-postgres"
REDIS_NAME="sec-redis"

# Generate secure passwords (only if not already set)
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)}"
POSTGRES_ADMIN_PASSWORD="${POSTGRES_ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)}"
REDIS_PASSWORD="${REDIS_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-$(openssl rand -hex 16)}"
AUTH_SECRET="${AUTH_SECRET:-$(openssl rand -base64 32)}"

# Connection URLs (using the custom service names)
DB_CONNECTION_URL="postgresql://infisical:${POSTGRES_PASSWORD}@${POSTGRES_NAME}.${NAMESPACE}.svc.cluster.local:5432/infisicalDB?sslmode=disable"
REDIS_URL="redis://:${REDIS_PASSWORD}@${REDIS_NAME}-master.${NAMESPACE}.svc.cluster.local:6379"

# Script directory (for relative paths)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Helper functions
print_header() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $1${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

ensure_namespace() {
    print_step "Ensuring namespace exists..."
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace '$NAMESPACE' ready"
    echo ""
}

ensure_helm_repos() {
    print_step "Adding Helm repositories..."
    helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
    helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/' 2>/dev/null || true
    helm repo update
    print_success "Helm repositories ready"
    echo ""
}
