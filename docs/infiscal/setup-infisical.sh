#!/bin/bash
# Infisical Self-Hosted Kubernetes Quick Start
# =============================================
# 
# This script helps you set up Infisical on Kubernetes
# 
# Usage: ./setup-infisical.sh [options]
#   --domain    Your domain (e.g., infisical.example.com)
#   --dev       Use development mode (in-cluster Postgres/Redis)
#   --help      Show this help message

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
DOMAIN=""
DEV_MODE=false
NAMESPACE="infisical"
OPERATOR_NAMESPACE="infisical-operator-system"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --dev)
            DEV_MODE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "  --domain <domain>  Your Infisical domain (required)"
            echo "  --dev              Development mode (in-cluster databases)"
            echo "  --help             Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validation
if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}Error: --domain is required${NC}"
    echo "Usage: $0 --domain infisical.example.com [--dev]"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Infisical Self-Hosted Kubernetes Setup               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Domain: ${GREEN}$DOMAIN${NC}"
echo -e "Mode: ${GREEN}$(if $DEV_MODE; then echo 'Development'; else echo 'Production'; fi)${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}helm not found. Please install helm first.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ kubectl found${NC}"
echo -e "${GREEN}✓ helm found${NC}"

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Connected to Kubernetes cluster${NC}"
echo ""

# Generate secrets
echo -e "${YELLOW}Generating encryption keys...${NC}"
ENCRYPTION_KEY=$(openssl rand -hex 16)
AUTH_SECRET=$(openssl rand -base64 32 | tr -d '\n')
DB_PASSWORD=$(openssl rand -base64 16 | tr -d '\n')
REDIS_PASSWORD=$(openssl rand -base64 16 | tr -d '\n')

echo -e "${GREEN}✓ Keys generated${NC}"
echo ""

# Step 1: Add Helm repository
echo -e "${YELLOW}[1/6] Adding Helm repository...${NC}"
helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/' 2>/dev/null || true
helm repo update
echo -e "${GREEN}✓ Helm repository added${NC}"
echo ""

# Step 2: Create namespace
echo -e "${YELLOW}[2/6] Creating namespace...${NC}"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓ Namespace created${NC}"
echo ""

# Step 3: Create secrets
echo -e "${YELLOW}[3/6] Creating Kubernetes secrets...${NC}"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: infisical-secrets
  namespace: $NAMESPACE
type: Opaque
stringData:
  ENCRYPTION_KEY: "$ENCRYPTION_KEY"
  AUTH_SECRET: "$AUTH_SECRET"
  SITE_URL: "https://$DOMAIN"
EOF

echo -e "${GREEN}✓ Secrets created${NC}"
echo ""

# Step 4: Create values file
echo -e "${YELLOW}[4/6] Creating Helm values...${NC}"

cat > /tmp/infisical-values.yaml <<EOF
nameOverride: "infisical"
fullnameOverride: "infisical"

infisical:
  enabled: true
  replicaCount: $(if $DEV_MODE; then echo 1; else echo 2; fi)
  image:
    repository: infisical/infisical
    tag: "v0.91.0-postgres"
    pullPolicy: IfNotPresent
  kubeSecretRef: "infisical-secrets"
  resources:
    limits:
      memory: 512Mi
    requests:
      cpu: 200m
      memory: 256Mi

ingress:
  enabled: true
  hostName: "$DOMAIN"
  ingressClassName: nginx
  nginx:
    enabled: true

postgresql:
  enabled: true
  fullnameOverride: "postgresql"
  auth:
    username: infisical
    password: "$DB_PASSWORD"
    database: infisicalDB
  primary:
    persistence:
      size: $(if $DEV_MODE; then echo '5Gi'; else echo '20Gi'; fi)

redis:
  enabled: true
  fullnameOverride: "redis"
  architecture: standalone
  auth:
    enabled: true
    password: "$REDIS_PASSWORD"
EOF

echo -e "${GREEN}✓ Values file created${NC}"
echo ""

# Step 5: Install Infisical
echo -e "${YELLOW}[5/6] Installing Infisical...${NC}"
helm upgrade --install infisical infisical-helm-charts/infisical-standalone \
  --namespace $NAMESPACE \
  --values /tmp/infisical-values.yaml \
  --wait \
  --timeout 10m

echo -e "${GREEN}✓ Infisical installed${NC}"
echo ""

# Step 6: Install Operator
echo -e "${YELLOW}[6/6] Installing Secrets Operator...${NC}"
kubectl create namespace $OPERATOR_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create global config
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: infisical-config
  namespace: $OPERATOR_NAMESPACE
data:
  hostAPI: "https://$DOMAIN/api"
EOF

helm upgrade --install infisical-secrets-operator infisical-helm-charts/secrets-operator \
  --namespace $OPERATOR_NAMESPACE \
  --wait

echo -e "${GREEN}✓ Operator installed${NC}"
echo ""

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    Setup Complete!                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Infisical is now deploying. Check status with:${NC}"
echo "  kubectl get pods -n $NAMESPACE"
echo ""
echo -e "${GREEN}Access Infisical at:${NC}"
echo "  https://$DOMAIN"
echo ""
echo -e "${YELLOW}Important: Make sure your DNS points $DOMAIN to your ingress IP:${NC}"
echo "  kubectl get ingress -n $NAMESPACE"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "  1. Create admin account at https://$DOMAIN"
echo "  2. Create a project and add secrets"
echo "  3. Create a Machine Identity for K8s operator"
echo "  4. Create InfisicalSecret CRDs to sync secrets"
echo ""
echo -e "${YELLOW}Save these generated values securely:${NC}"
echo "  ENCRYPTION_KEY: $ENCRYPTION_KEY"
echo "  AUTH_SECRET: $AUTH_SECRET"
echo ""

# Cleanup
rm -f /tmp/infisical-values.yaml
