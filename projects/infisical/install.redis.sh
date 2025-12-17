#!/bin/bash
# =============================================================================
# Redis Installation Script
# =============================================================================
set -e

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/install.core.sh"

print_header "Deploying Redis as '${REDIS_NAME}'"

echo -e "Namespace:    ${GREEN}$NAMESPACE${NC}"
echo -e "Redis:        ${GREEN}$REDIS_NAME (v$REDIS_VERSION)${NC}"
echo ""

# Ensure prerequisites
ensure_helm_repos
ensure_namespace

# Deploy Redis
print_step "Deploying Redis..."

cat > "${SCRIPT_DIR}/redis-values.yaml" <<EOF
fullnameOverride: "${REDIS_NAME}"

global:
  redis:
    password: "${REDIS_PASSWORD}"

architecture: standalone

auth:
  enabled: true

master:
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 128Mi
  persistence:
    enabled: true
    storageClass: "manual"
    size: 5Gi
  podSecurityContext:
    enabled: true
    fsGroup: 1001
  containerSecurityContext:
    enabled: true
    runAsUser: 1001
    runAsNonRoot: true
  configuration: |
    maxmemory 256mb
    maxmemory-policy allkeys-lru
    appendonly yes
EOF

helm upgrade --install ${REDIS_NAME} bitnami/redis \
  --namespace $NAMESPACE \
  --values "${SCRIPT_DIR}/redis-values.yaml" \
  --wait \
  --timeout 60m

print_success "Redis deployed as '${REDIS_NAME}'"
echo ""
echo -e "Connection: ${GREEN}${REDIS_NAME}-master.${NAMESPACE}.svc.cluster.local:6379${NC}"
echo ""

# Output credentials if running standalone
if [[ "${STANDALONE_RUN:-false}" == "true" ]]; then
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  SAVE THESE CREDENTIALS SECURELY                             ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "REDIS_PASSWORD:        ${RED}$REDIS_PASSWORD${NC}"
    echo ""
fi
