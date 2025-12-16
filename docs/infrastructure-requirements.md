# Infrastructure Requirements

Prerequisites and cluster setup for running noizu.com Kubernetes deployments.

## Cluster Requirements

### Kubernetes Version

- Minimum: v1.19+
- Recommended: v1.25+

### Required Components

| Component | Purpose | Notes |
|-----------|---------|-------|
| NGINX Ingress Controller | External traffic routing | Handles TLS termination |
| Longhorn | Distributed block storage | Persistent volumes |
| Helm 3.x | Package management | Chart deployment |
| cert-manager (optional) | Certificate automation | Alternative to manual TLS |

## NGINX Ingress Controller

### Installation

```bash
# Using Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

### Verification

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

### Required Annotations

All ingress resources use:
```yaml
annotations:
  nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
```

## Longhorn Storage

### Installation

```bash
# Using Helm
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace
```

### Verification

```bash
kubectl get pods -n longhorn-system
kubectl get sc
```

### Storage Class

Longhorn should create a `longhorn` storage class:
```bash
kubectl get sc longhorn
```

If not default:
```bash
kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## Host Path Volumes

All projects use host path volumes under `/k8-volumes/`:

```
/k8-volumes/
├── hakatime.noizu.com/
│   └── ts-disk/
├── ntm.noizu.com/
│   └── redis-disk/
├── nb.noizu.com/
│   ├── live-book-data/
│   ├── redis-data/
│   └── ts-data/
├── noizu.com/
│   ├── ts-disk/
│   ├── redis-disk/
│   └── wp-disk/
└── therobotlives.com/
    ├── ts-disk/
    └── wp-disk/
```

### Create Directories

On each node:
```bash
sudo mkdir -p /k8-volumes/hakatime.noizu.com/ts-disk
sudo mkdir -p /k8-volumes/ntm.noizu.com/redis-disk
sudo mkdir -p /k8-volumes/nb.noizu.com/{live-book-data,redis-data,ts-data}
sudo mkdir -p /k8-volumes/noizu.com/{ts-disk,redis-disk,wp-disk}
sudo mkdir -p /k8-volumes/therobotlives.com/{ts-disk,wp-disk}

# Set permissions
sudo chmod -R 777 /k8-volumes
```

## DNS Configuration

Each project requires DNS records pointing to the Ingress IP:

| Domain | Type | Target |
|--------|------|--------|
| hakatime.noizu.com | A/CNAME | Ingress IP/LB |
| ntm.noizu.com | A/CNAME | Ingress IP/LB |
| nb.noizu.com | A/CNAME | Ingress IP/LB |
| noizu.com | A/CNAME | Ingress IP/LB |
| therobotlives.com | A/CNAME | Ingress IP/LB |

### Get Ingress IP

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## TLS Certificates

### Cloudflare Origin Certificates

All projects use Cloudflare Origin certificates stored as Kubernetes secrets.

**Creating TLS Secret:**

```bash
kubectl create secret tls cloudflare-<domain>-tls \
  --cert=<domain>.pem \
  --key=<domain>.key \
  -n <namespace>
```

**Or from YAML file:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-<domain>-tls
  namespace: <namespace>
type: kubernetes.io/tls
data:
  tls.crt: <base64-encoded-cert>
  tls.key: <base64-encoded-key>
```

### Certificate Naming Convention

Pattern: `cloudflare-<domain>-tls`

| Domain | Secret Name |
|--------|-------------|
| hakatime.noizu.com | `cloudflare-hakatime.noizu.com-tls` |
| ntm.noizu.com | `cloudflare-ntm.noizu.com-tls` |
| nb.noizu.com | `cloudflare-nb-noizu.com-tls` |
| therobotlives.com | `cloudflare-therobotlives.com-tls` |

## Docker Registries

### Private Registry: ops.noizu.com

Used for custom application images.

**Create Secret:**
```bash
kubectl create secret docker-registry ops-registry-secret \
  --docker-server=ops.noizu.com \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  -n <namespace>
```

### Docker Hub

For public images and some custom images.

**Create Secret:**
```bash
kubectl create secret docker-registry docker-registry-secret \
  --docker-server=docker.io \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  -n <namespace>
```

### Patch Service Account

```bash
kubectl patch serviceaccount default \
  -p '{"imagePullSecrets": [{"name": "ops-registry-secret"}, {"name": "docker-registry-secret"}]}' \
  -n <namespace>
```

## Resource Recommendations

### Node Resources

For a single-node development/small production setup:

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 4 cores | 8+ cores |
| RAM | 8 GB | 16+ GB |
| Storage | 100 GB | 500+ GB SSD |

### Per-Application Resources

| Application | CPU Request | Memory Request | Storage |
|-------------|-------------|----------------|---------|
| Hakatime Server | 100m | 256Mi | - |
| TimescaleDB | 500m | 1Gi | 50Gi |
| Elixir App | 200m | 512Mi | - |
| Redis | 100m | 128Mi | 5-25Gi |
| WordPress | 200m | 256Mi | 10-25Gi |
| MySQL | 500m | 512Mi | 10-25Gi |
| Livebook | 500m | 1Gi | 25Gi |

**Note**: Current deployments don't specify resource limits. Consider adding:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "256Mi"
  limits:
    cpu: "500m"
    memory: "512Mi"
```

## Network Requirements

### Ports

| Port | Protocol | Service |
|------|----------|---------|
| 80 | TCP | HTTP (redirects to HTTPS) |
| 443 | TCP | HTTPS |
| 6443 | TCP | Kubernetes API (internal) |

### Internal Services

All application services use ClusterIP (internal only):
- Application servers: 80
- PostgreSQL/TimescaleDB: 5432
- Redis: 6379
- Livebook: 8080

## Backup Considerations

### Database Backups

```bash
# PostgreSQL/TimescaleDB
kubectl exec -it <db-pod> -n <namespace> -- pg_dumpall -U <user> > backup.sql

# MySQL
kubectl exec -it <db-pod> -n <namespace> -- mysqldump -u root -p<password> --all-databases > backup.sql
```

### Volume Backups

Longhorn supports:
- Scheduled snapshots
- Backup to S3-compatible storage

```bash
# Create snapshot via Longhorn UI or:
kubectl -n longhorn-system get volume
```

## Monitoring (Optional)

Consider adding:
- Prometheus + Grafana for metrics
- Loki for log aggregation
- Alertmanager for alerts

```bash
# Prometheus stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
```

## Checklist

Before deploying:

- [ ] Kubernetes cluster running (v1.19+)
- [ ] NGINX Ingress Controller installed
- [ ] Longhorn storage provisioner installed
- [ ] Helm 3.x installed
- [ ] Host path directories created
- [ ] DNS records configured
- [ ] TLS certificates obtained from Cloudflare
- [ ] Docker registry credentials available
- [ ] Database passwords/secrets prepared
