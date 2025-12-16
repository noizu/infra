# Infisical Self-Hosted Kubernetes Setup Guide

Complete guide to deploying Infisical on Kubernetes and using the operator to sync secrets.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Your Kubernetes Cluster                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐         ┌──────────────────────────────┐  │
│  │  Infisical       │         │  Infisical Secrets Operator  │  │
│  │  (Self-Hosted)   │◄────────│                              │  │
│  │                  │         │  Watches InfisicalSecret CRDs│  │
│  │  - API Server    │         │  Creates K8s Secrets         │  │
│  │  - Web UI        │         └──────────────────────────────┘  │
│  │  - PostgreSQL    │                     │                     │
│  │  - Redis         │                     ▼                     │
│  └──────────────────┘         ┌──────────────────────────────┐  │
│                               │  Managed K8s Secrets         │  │
│                               │  (auto-synced from Infisical)│  │
│                               └──────────────────────────────┘  │
│                                           │                     │
│                                           ▼                     │
│                               ┌──────────────────────────────┐  │
│                               │  Your Application Pods       │  │
│                               │  (consume secrets via env    │  │
│                               │   vars or volume mounts)     │  │
│                               └──────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Part 1: Deploy Self-Hosted Infisical

### Prerequisites

- Kubernetes cluster (1.19+)
- Helm 3.11.3+
- kubectl configured
- (Optional) External PostgreSQL and Redis for production

### Step 1: Add Helm Repository

```bash
helm repo add infisical-helm-charts 'https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/'
helm repo update
```

### Step 2: Create Namespace

```bash
kubectl create namespace infisical
```

### Step 3: Generate Required Secrets

```bash
# Generate random keys
ENCRYPTION_KEY=$(openssl rand -hex 16)
AUTH_SECRET=$(openssl rand -base64 32)

echo "ENCRYPTION_KEY: $ENCRYPTION_KEY"
echo "AUTH_SECRET: $AUTH_SECRET"
```

### Step 4: Create Kubernetes Secret for Infisical Config

#### For Development/PoC (uses in-cluster Postgres & Redis):

```yaml
# infisical-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: infisical-secrets
  namespace: infisical
type: Opaque
stringData:
  ENCRYPTION_KEY: "<your-generated-encryption-key>"
  AUTH_SECRET: "<your-generated-auth-secret>"
  SITE_URL: "https://infisical.yourdomain.com"  # or use the ingress IP
```

#### For Production (external Postgres & Redis):

```yaml
# infisical-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: infisical-secrets
  namespace: infisical
type: Opaque
stringData:
  ENCRYPTION_KEY: "<your-generated-encryption-key>"
  AUTH_SECRET: "<your-generated-auth-secret>"
  SITE_URL: "https://infisical.yourdomain.com"
  DB_CONNECTION_URI: "postgresql://user:password@postgres-host:5432/infisical?sslmode=require"
  REDIS_URL: "redis://:password@redis-host:6379"
```

Apply the secret:

```bash
kubectl apply -f infisical-secrets.yaml
```

### Step 5: Create Helm Values File

```yaml
# values.yaml
nameOverride: "infisical"
fullnameOverride: "infisical"

infisical:
  enabled: true
  name: infisical
  autoDatabaseSchemaMigration: true
  replicaCount: 2  # Use 1 for dev, 2+ for production
  
  image:
    repository: infisical/infisical
    tag: "v0.91.0-postgres"  # Check https://hub.docker.com/r/infisical/infisical/tags for latest
    pullPolicy: IfNotPresent
  
  kubeSecretRef: "infisical-secrets"
  
  service:
    type: ClusterIP
  
  resources:
    limits:
      memory: 512Mi
    requests:
      cpu: 200m
      memory: 256Mi

ingress:
  enabled: true
  hostName: "infisical.yourdomain.com"  # Change this
  ingressClassName: nginx
  nginx:
    enabled: true
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
  tls:
    - secretName: infisical-tls
      hosts:
        - infisical.yourdomain.com

# For PoC - enable in-cluster databases
# For production - set enabled: false and use external services
postgresql:
  enabled: true  # Set to false for production
  fullnameOverride: "postgresql"
  auth:
    username: infisical
    password: "<strong-password>"  # Change this!
    database: infisicalDB
  primary:
    persistence:
      size: 10Gi

redis:
  enabled: true  # Set to false for production
  fullnameOverride: "redis"
  architecture: standalone
  auth:
    enabled: true
    password: "<strong-password>"  # Change this!
```

### Step 6: Install Infisical

```bash
helm upgrade --install infisical infisical-helm-charts/infisical-standalone \
  --namespace infisical \
  --values values.yaml
```

### Step 7: Verify Deployment

```bash
# Check pods
kubectl get pods -n infisical

# Check ingress
kubectl get ingress -n infisical

# Watch logs
kubectl logs -n infisical -l app.kubernetes.io/name=infisical -f
```

### Step 8: Initial Setup

1. Access the Infisical UI via your ingress hostname
2. Create your admin account
3. Create an organization
4. Create your first project

---

## Part 2: Install Infisical Secrets Operator

The operator syncs secrets from Infisical into native Kubernetes Secrets.

### Step 1: Install the Operator

```bash
# Cluster-wide installation
helm install infisical-secrets-operator infisical-helm-charts/secrets-operator \
  --namespace infisical-operator-system \
  --create-namespace
```

Or for namespace-scoped installation:

```bash
helm install infisical-secrets-operator infisical-helm-charts/secrets-operator \
  --namespace my-app-namespace \
  --set scopedNamespace=my-app-namespace \
  --set scopedRBAC=true
```

### Step 2: Verify Operator Installation

```bash
kubectl get pods -n infisical-operator-system
kubectl get crds | grep infisical
```

You should see these CRDs:
- `infisicalsecrets.secrets.infisical.com`
- `infisicalpushsecrets.secrets.infisical.com`
- `infisicaldynamicsecrets.secrets.infisical.com`

---

## Part 3: Configure Authentication

### Option A: Universal Auth (Recommended for Getting Started)

#### 1. Create a Machine Identity in Infisical

1. Go to Infisical UI → Organization Settings → Machine Identities
2. Click "Create Identity"
3. Name it (e.g., "k8s-operator")
4. Under Authentication, enable "Universal Auth"
5. Generate a Client ID and Client Secret
6. Add the identity to your project with appropriate role (e.g., "Member" or "Developer")

#### 2. Store Credentials in Kubernetes

```bash
kubectl create secret generic universal-auth-credentials \
  --from-literal=clientId="<your-client-id>" \
  --from-literal=clientSecret="<your-client-secret>" \
  --namespace default  # Change to your app namespace
```

### Option B: Kubernetes Auth (More Secure, No Static Secrets)

#### 1. Create a Reviewer Service Account

```yaml
# infisical-reviewer-sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: infisical-auth-reviewer
  namespace: infisical-operator-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: infisical-auth-reviewer-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: infisical-auth-reviewer
    namespace: infisical-operator-system
```

```bash
kubectl apply -f infisical-reviewer-sa.yaml
```

#### 2. Get the Service Account Token

```bash
# Create a long-lived token for the reviewer service account
kubectl create token infisical-auth-reviewer \
  --namespace infisical-operator-system \
  --duration=8760h  # 1 year
```

#### 3. Configure Kubernetes Auth in Infisical

1. Go to Infisical UI → Organization Settings → Machine Identities
2. Create a new identity
3. Under Authentication, enable "Kubernetes Auth"
4. Configure:
   - **Kubernetes Host**: Your cluster's API server URL
   - **Token Reviewer JWT**: The token from step 2
   - **CA Certificate**: Your cluster's CA cert (optional if public)
   - **Allowed Namespaces**: Restrict which namespaces can authenticate
   - **Allowed Service Account Names**: Restrict which SAs can auth

---

## Part 4: Create InfisicalSecret CRD

### Example 1: Universal Auth - Sync All Secrets

```yaml
# infisical-secret.yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: my-app-secrets
  namespace: default
  annotations:
    # Optional: trigger deployment restarts on secret change
    secrets.infisical.com/auto-reload: "true"
spec:
  # Point to your self-hosted instance
  hostAPI: https://infisical.yourdomain.com/api
  
  # How often to check for updates (seconds)
  resyncInterval: 60
  
  authentication:
    universalAuth:
      credentialsRef:
        secretName: universal-auth-credentials
        secretNamespace: default
      secretsScope:
        projectSlug: my-project-slug    # From Infisical URL
        envSlug: prod                    # dev, staging, prod, etc.
        secretsPath: "/"                 # Root path or subfolder
        recursive: true                  # Include subfolders
  
  managedSecretReference:
    secretName: my-app-managed-secret   # K8s secret to create
    secretNamespace: default
    creationPolicy: Owner               # Owner = delete with CRD, Orphan = keep
```

### Example 2: Kubernetes Auth

```yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: my-app-secrets
  namespace: default
spec:
  hostAPI: https://infisical.yourdomain.com/api
  resyncInterval: 60
  
  authentication:
    kubernetesAuth:
      identityId: "<machine-identity-id-from-infisical>"
      serviceAccountRef:
        name: my-app-service-account
        namespace: default
      secretsScope:
        projectSlug: my-project-slug
        envSlug: prod
        secretsPath: "/"
  
  managedSecretReference:
    secretName: my-app-managed-secret
    secretNamespace: default
    creationPolicy: Owner
```

### Example 3: With Secret Templating

```yaml
apiVersion: secrets.infisical.com/v1alpha1
kind: InfisicalSecret
metadata:
  name: my-app-secrets
  namespace: default
spec:
  hostAPI: https://infisical.yourdomain.com/api
  resyncInterval: 60
  
  authentication:
    universalAuth:
      credentialsRef:
        secretName: universal-auth-credentials
        secretNamespace: default
      secretsScope:
        projectSlug: my-project
        envSlug: prod
        secretsPath: "/"
  
  managedSecretReference:
    secretName: my-app-config
    secretNamespace: default
    creationPolicy: Owner
    # Custom secret type (default is Opaque)
    # secretType: kubernetes.io/dockerconfigjson
  
  # Template to customize output format
  template:
    includeAllSecrets: false
    data:
      # Map Infisical secrets to K8s secret keys
      DATABASE_URL: "{{ .DB_HOST.Value }}:{{ .DB_PORT.Value }}/{{ .DB_NAME.Value }}"
      REDIS_CONNECTION: "redis://:{{ .REDIS_PASSWORD.Value }}@{{ .REDIS_HOST.Value }}:6379"
      # Direct mapping
      API_KEY: "{{ .API_KEY.Value }}"
```

### Apply the CRD

```bash
kubectl apply -f infisical-secret.yaml
```

### Verify Sync

```bash
# Check InfisicalSecret status
kubectl describe infisicalsecret my-app-secrets

# Check if managed secret was created
kubectl get secret my-app-managed-secret -o yaml

# Check operator logs for issues
kubectl logs -n infisical-operator-system -l app.kubernetes.io/name=secrets-operator -f
```

---

## Part 5: Using Secrets in Your Deployments

### Option A: Environment Variables from Secret

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  annotations:
    # Auto-restart when secret changes (requires operator annotation)
    secrets.infisical.com/auto-reload: "true"
spec:
  template:
    spec:
      containers:
        - name: my-app
          image: my-app:latest
          envFrom:
            - secretRef:
                name: my-app-managed-secret
```

### Option B: Specific Environment Variables

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        - name: my-app
          image: my-app:latest
          env:
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: my-app-managed-secret
                  key: DATABASE_PASSWORD
            - name: API_KEY
              valueFrom:
                secretKeyRef:
                  name: my-app-managed-secret
                  key: API_KEY
```

### Option C: Volume Mount

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        - name: my-app
          image: my-app:latest
          volumeMounts:
            - name: secrets
              mountPath: /etc/secrets
              readOnly: true
      volumes:
        - name: secrets
          secret:
            secretName: my-app-managed-secret
```

---

## Part 6: Global Operator Configuration

Configure defaults for all InfisicalSecret CRDs:

```yaml
# infisical-global-config.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: infisical-operator-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: infisical-config
  namespace: infisical-operator-system
data:
  # Default API host for all CRDs
  hostAPI: https://infisical.yourdomain.com/api
  
  # TLS settings for self-signed certs (optional)
  # tls.caRef.secretName: custom-ca-certificate
  # tls.caRef.secretNamespace: default
  # tls.caRef.key: ca.crt
```

```bash
kubectl apply -f infisical-global-config.yaml
```

---

## Troubleshooting

### Check Operator Status

```bash
# Operator pods
kubectl get pods -n infisical-operator-system

# Operator logs
kubectl logs -n infisical-operator-system deployment/infisical-secrets-operator-controller-manager -f

# InfisicalSecret status
kubectl describe infisicalsecret <name>
```

### Common Issues

| Issue | Solution |
|-------|----------|
| `no authentication method provided` | Check credentialsRef secret exists and has correct keys (`clientId`, `clientSecret`) |
| `Failed to sync secrets` | Verify hostAPI URL is correct and reachable from cluster |
| `Missing workspace id` | Ensure `projectSlug` matches exactly (check Infisical URL) |
| Secret not updating | Check `resyncInterval`, delete and recreate InfisicalSecret if needed |
| TLS errors | Configure `tls.caRef` if using self-signed certificates |

### Verify Connectivity

```bash
# Test API connectivity from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v https://infisical.yourdomain.com/api/status
```

---

## Quick Reference

### Helm Commands

```bash
# Update Infisical
helm upgrade infisical infisical-helm-charts/infisical-standalone \
  --namespace infisical --values values.yaml

# Update Operator
helm upgrade infisical-secrets-operator infisical-helm-charts/secrets-operator \
  --namespace infisical-operator-system

# Uninstall
helm uninstall infisical -n infisical
helm uninstall infisical-secrets-operator -n infisical-operator-system
```

### Useful kubectl Commands

```bash
# List all InfisicalSecrets
kubectl get infisicalsecrets --all-namespaces

# Force resync (delete and recreate)
kubectl delete infisicalsecret <name> && kubectl apply -f <file>

# Check managed secrets
kubectl get secrets -l secrets.infisical.com/managed=true
```
