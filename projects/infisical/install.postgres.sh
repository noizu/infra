#!/bin/bash
# =============================================================================
# PostgreSQL Installation Script
# =============================================================================
set -e

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/install.core.sh"

print_header "Deploying PostgreSQL as '${POSTGRES_NAME}'"

echo -e "Namespace:    ${GREEN}$NAMESPACE${NC}"
echo -e "PostgreSQL:   ${GREEN}$POSTGRES_NAME (v$POSTGRES_VERSION)${NC}"
echo ""

# Ensure prerequisites
ensure_helm_repos
ensure_namespace

# Deploy PostgreSQL
print_step "Deploying PostgreSQL..."

cat > "${SCRIPT_DIR}/postgres-values.yaml" <<EOF
fullnameOverride: "${POSTGRES_NAME}"

global:
  postgresql:
    auth:
      database: infisicalDB
      username: infisical
      password: "${POSTGRES_PASSWORD}"
      postgresPassword: "${POSTGRES_ADMIN_PASSWORD}"

architecture: standalone

primary:
  resources:
    limits:
      cpu: "1"
      memory: 1Gi
    requests:
      cpu: 250m
      memory: 256Mi
  persistence:
    enabled: true
    storageClass: "manual"
    size: 20Gi
  podSecurityContext:
    enabled: true
    fsGroup: 1001
  containerSecurityContext:
    enabled: true
    runAsUser: 1001
    runAsNonRoot: true
  configuration: |
    max_connections = 200
    shared_buffers = 256MB
    password_encryption = scram-sha-256
    log_statement = 'ddl'
    listen_addresses = '*'
  initdb:
    scripts:
      init.sql: |
        CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        CREATE EXTENSION IF NOT EXISTS "pgcrypto";
EOF

helm upgrade --install ${POSTGRES_NAME} bitnami/postgresql \
  --namespace $NAMESPACE \
  --values "${SCRIPT_DIR}/postgres-values.yaml" \
  --wait \
  --timeout 60m

print_success "PostgreSQL deployed as '${POSTGRES_NAME}'"
echo ""
echo -e "Connection: ${GREEN}${POSTGRES_NAME}.${NAMESPACE}.svc.cluster.local:5432${NC}"
echo ""

# Output credentials if running standalone
if [[ "${STANDALONE_RUN:-false}" == "true" ]]; then
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  SAVE THESE CREDENTIALS SECURELY                             ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "POSTGRES_PASSWORD:     ${RED}$POSTGRES_PASSWORD${NC}"
    echo -e "POSTGRES_ADMIN_PASS:   ${RED}$POSTGRES_ADMIN_PASSWORD${NC}"
    echo ""
fi
