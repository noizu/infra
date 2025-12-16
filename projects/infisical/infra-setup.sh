#!/bin/bash
# =============================================================================
# Infisical + Bitnami PostgreSQL/Redis Deployment Script
# =============================================================================
set -e

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

# Generate secure passwords
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)}"
POSTGRES_ADMIN_PASSWORD="${POSTGRES_ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)}"
REDIS_PASSWORD="${REDIS_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-$(openssl rand -hex 16)}"
AUTH_SECRET="${AUTH_SECRET:-$(openssl rand -base64 32)}"

# Service names
POSTGRES_NAME="sec-postgres"
REDIS_NAME="sec-redis"

# Connection URLs (using the custom service names)
DB_CONNECTION_URL="postgresql://infisical:${POSTGRES_PASSWORD}@${POSTGRES_NAME}.${NAMESPACE}.svc.cluster.local:5432/infisicalDB?sslmode=disable"
REDIS_URL="redis://:${REDIS_PASSWORD}@${REDIS_NAME}-master.${NAMESPACE}.svc.cluster.local:6379"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Infisical + Bitnami PostgreSQL/Redis Deployment              ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Namespace:    ${GREEN}$NAMESPACE${NC}"
echo -e "Domain:       ${GREEN}$DOMAIN${NC}"
echo -e "PostgreSQL:   ${GREEN}$POSTGRES_NAME (v$POSTGRES_VERSION)${NC}"
echo -e "PostgreSQL:   ${GREEN}${DB_CONNECTION_URL}${NC}"
echo -e "Redis:        ${GREEN}$REDIS_NAME (v$REDIS_VERSION)${NC}"
echo -e "Infisical:    ${GREEN}$INFISICAL_VERSION${NC}"
echo ""

# =============================================================================
# Step 1: Add Helm repositories
# =============================================================================
echo -e "${YELLOW}[1/6] Adding Helm repositories...${NC}"
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/' 2>/dev/null || true
helm repo update
echo -e "${GREEN}✓ Helm repositories ready${NC}"
echo ""

# =============================================================================
# Step 2: Create namespace
# =============================================================================
echo -e "${YELLOW}[2/6] Creating namespace...${NC}"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespace ready${NC}"
echo ""

# =============================================================================
# Step 3: Deploy PostgreSQL
# =============================================================================
echo -e "${YELLOW}[3/6] Deploying PostgreSQL as '${POSTGRES_NAME}'...${NC}"

cat > ./postgres-values.yaml <<EOF
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
  --values ./postgres-values.yaml \
  --wait \
  --timeout 5m

echo -e "${GREEN}✓ PostgreSQL deployed as '${POSTGRES_NAME}'${NC}"
echo ""

# =============================================================================
# Step 4: Deploy Redis
# =============================================================================
echo -e "${YELLOW}[4/6] Deploying Redis as '${REDIS_NAME}'...${NC}"

cat > ./redis-values.yaml <<EOF
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
  --values ./redis-values.yaml \
  --wait \
  --timeout 5m

echo -e "${GREEN}✓ Redis deployed as '${REDIS_NAME}'${NC}"
echo ""

# =============================================================================
# Step 5: Create Infisical secrets
# =============================================================================
echo -e "${YELLOW}[5/6] Creating Infisical configuration...${NC}"

cat > ./infisical-secrets.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: infisical-secrets
  namespace: $NAMESPACE
type: Opaque
stringData:
  ENCRYPTION_KEY: "${ENCRYPTION_KEY}"
  AUTH_SECRET: "${AUTH_SECRET}"
  SITE_URL: "https://${DOMAIN}"
  DB_CONNECTION_URI: "${DB_CONNECTION_URL}"
  REDIS_URL: "${REDIS_URL}"
EOF

kubectl apply -f ./infisical-secrets.yaml -n ${NAMESPACE}

echo -e "${GREEN}✓ Infisical secrets created${NC}"
echo ""

# =============================================================================
# Step 6: Deploy Infisical
# =============================================================================
echo -e "${YELLOW}[6/6] Deploying Infisical...${NC}"

cat > ./infisical-values.yaml <<EOF
nameOverride: "infisical"
fullnameOverride: "infisical"

infisical:
  enabled: true
  replicaCount: 2
  env:
    - name: DEBUG
      value: "true"
    - name: LOG_LEVEL
      value: "debug"  
  image:
    repository: infisical/infisical
    tag: "${INFISICAL_VERSION}"
    pullPolicy: IfNotPresent
  kubeSecretRef: "infisical-secrets"
  autoDatabaseSchemaMigration: true
  resources:
    limits:
      memory: 2048Mi
    requests:
      cpu: 200m
      memory: 512Mi

ingress:
  enabled: true
  hostName: "${DOMAIN}"
  ingressClassName: nginx
  nginx:
    enabled: true

# Disable in-cluster databases (using external Bitnami charts)
postgresql:
  enabled: false

redis:
  enabled: false

EOF

helm upgrade --install infisical infisical-helm-charts/infisical-standalone \
  --namespace $NAMESPACE \
  --values ./infisical-values.yaml \
  --wait \
  --timeout 10m

echo -e "${GREEN}✓ Infisical deployed${NC}"
echo ""

# =============================================================================
# Summary
# =============================================================================
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Deployment Complete!                       ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Services deployed:${NC}"
kubectl get pods -n $NAMESPACE
echo ""
echo -e "${GREEN}Service endpoints:${NC}"
echo -e "  PostgreSQL: ${POSTGRES_NAME}.${NAMESPACE}.svc.cluster.local:5432"
echo -e "  Redis:      ${REDIS_NAME}.${NAMESPACE}.svc.cluster.local:6379"
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
# rm -f ./postgres-values.yaml ./redis-values.yaml ./infisical-values.yaml