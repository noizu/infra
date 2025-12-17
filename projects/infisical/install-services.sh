#!/bin/bash
# =============================================================================
# Infisical + Bitnami PostgreSQL/Redis Deployment Script
# =============================================================================
set -e

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/install.core.sh"

print_header "Infisical + Bitnami PostgreSQL/Redis Deployment              "

echo -e "Namespace:    ${GREEN}$NAMESPACE${NC}"
echo -e "Domain:       ${GREEN}$DOMAIN${NC}"
echo -e "PostgreSQL:   ${GREEN}$POSTGRES_NAME (v$POSTGRES_VERSION)${NC}"
echo -e "Redis:        ${GREEN}$REDIS_NAME (v$REDIS_VERSION)${NC}"
echo -e "Infisical:    ${GREEN}$INFISICAL_VERSION${NC}"
echo ""

# =============================================================================
# Step 1: Add Helm repositories
# =============================================================================
print_step "[1/5] Adding Helm repositories..."
ensure_helm_repos

# =============================================================================
# Step 2: Create namespace
# =============================================================================
print_step "[2/5] Creating namespace..."
ensure_namespace

# =============================================================================
# Step 3: Deploy PostgreSQL
# =============================================================================
print_step "[3/5] Deploying PostgreSQL..."
source "${SCRIPT_DIR}/install.postgres.sh"

# =============================================================================
# Step 4: Deploy Redis
# =============================================================================
print_step "[4/5] Deploying Redis..."
source "${SCRIPT_DIR}/install.redis.sh"

# =============================================================================
# Step 5: Deploy Infisical
# =============================================================================
print_step "[5/5] Deploying Infisical..."
source "${SCRIPT_DIR}/install.infisical.sh"

# =============================================================================
# Summary
# =============================================================================
print_header "Deployment Complete!                                          "

echo -e "${GREEN}Services deployed:${NC}"
kubectl get pods -n $NAMESPACE
echo ""
echo -e "${GREEN}Service endpoints:${NC}"
echo -e "  PostgreSQL: ${POSTGRES_NAME}.${NAMESPACE}.svc.cluster.local:5432"
echo -e "  Redis:      ${REDIS_NAME}-master.${NAMESPACE}.svc.cluster.local:6379"
echo -e "  Infisical:  https://${DOMAIN}"
echo ""
echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║  CRITICAL: SAVE THESE VALUES SECURELY (CANNOT BE RECOVERED)  ║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "ENCRYPTION_KEY:        ${RED}$ENCRYPTION_KEY${NC}"
echo -e "AUTH_SECRET:           ${RED}$AUTH_SECRET${NC}"
echo -e "POSTGRES_PASSWORD:     ${RED}$POSTGRES_PASSWORD${NC}"
echo -e "POSTGRES_ADMIN_PASS:   ${RED}$POSTGRES_ADMIN_PASSWORD${NC}"
echo -e "REDIS_PASSWORD:        ${RED}$REDIS_PASSWORD${NC}"
echo ""
echo -e "${YELLOW}Without ENCRYPTION_KEY, your secrets cannot be decrypted!${NC}"
echo ""

# Cleanup temp files (uncomment for production)
# rm -f "${SCRIPT_DIR}/postgres-values.yaml" "${SCRIPT_DIR}/redis-values.yaml" "${SCRIPT_DIR}/infisical-values.yaml"
