#!/bin/bash
# =============================================================================
# Infisical Installation Script
# =============================================================================
set -e

# Source shared configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_DIR="$SCRIPT_DIR/values"
source "${SCRIPT_DIR}/install.core.sh"

print_header "Deploying Infisical"

echo -e "Namespace:    ${GREEN}$NAMESPACE${NC}"
echo -e "Domain:       ${GREEN}$DOMAIN${NC}"
echo -e "Infisical:    ${GREEN}$INFISICAL_VERSION${NC}"
echo ""

# Ensure prerequisites
ensure_helm_repos
ensure_namespace

# Create Infisical secrets
print_step "Creating Infisical secrets..."

cat > "${SCRIPT_DIR}/secrets/infisical-secrets.yaml" <<EOF
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

kubectl apply -f "${SCRIPT_DIR}/secrets/infisical-secrets.yaml" -n ${NAMESPACE}

print_success "Infisical secrets created"
echo ""

# Deploy Infisical
print_step "Deploying Infisical..."

cat > "${SCRIPT_DIR}/values/infisical-values.yaml" <<EOF
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
    - name: SMTP_HOST
      value: smtp.sendgrid.net
    - name: SMTP_USERNAME
      value: apikey
    - name: SMTP_PASSWORD
      value: $SENDGRID_API_KEY
    - name: SMTP_PORT
      value: 587
    - name: SMTP_FROM_ADDRESS
      value: $INFISICAL_SYSTEM_EMAIL
    - name: SMTP_FROM_NAME
      value: Noizu Infisical
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
  createIngressClass: $CREATE_INGRESS
  nginx:
    enabled: false

# Disable in-cluster databases (using external Bitnami charts)
postgresql:
  enabled: false

redis:
  enabled: false

EOF

helm upgrade --install infisical infisical-helm-charts/infisical-standalone \
  --namespace $NAMESPACE \
  --values "${SCRIPT_DIR}/values/infisical-values.yaml" \
  --wait \
  --timeout 60m

print_success "Infisical deployed"
echo ""
echo -e "URL: ${GREEN}https://${DOMAIN}${NC}"
echo ""

# Output credentials if running standalone
if [[ "${STANDALONE_RUN:-false}" == "true" ]]; then
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  CRITICAL: SAVE THESE VALUES SECURELY (CANNOT BE RECOVERED)  ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "ENCRYPTION_KEY:        ${RED}$ENCRYPTION_KEY${NC}"
    echo -e "AUTH_SECRET:           ${RED}$AUTH_SECRET${NC}"
    echo ""
    echo -e "${YELLOW}Without ENCRYPTION_KEY, your secrets cannot be decrypted!${NC}"
    echo ""
fi
