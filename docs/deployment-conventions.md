# Kubernetes Deployment Conventions

This document describes the Kubernetes deployment conventions and processes used across noizu.com projects.

## Overview

All projects follow a consistent pattern:
- **Helm charts** for templating and deployment management
- **NGINX Ingress** for external traffic routing with TLS
- **Longhorn** for persistent storage
- **Cloudflare TLS certificates** for HTTPS
- **Environment-based secrets** injected via Helm

## Projects Summary

| Project | Namespace | Domain | Chart Name |
|---------|-----------|--------|------------|
| hakatime | `haka-ns` | hakatime.noizu.com | noizu-hakatime |
| blog (wordpress) | `trl-wp` | therobotlives.com | trl-wp |
| jira_magic | `ntm-n` | ntm.noizu.com | ntm.noizu.com-prod |
| live-book | `nlb` | nb.noizu.com | noizu-lb |
| task_magic | `ntm-n` | ntm.noizu.com | ntm.noizu.com-prod |
| website (phx) | `noizu-website-namespace` | noizu.com | noizu.com-prod |
| website (wordpress) | `noizu-wp` | noizu.com | noizu.com-wp |

## Directory Structure

Each project follows this structure:

```
project/
├── kubernetes/                     # or wordpress.k8/ for WP projects
│   ├── namespace.yaml             # Namespace definition
│   ├── volume.yaml                # PersistentVolume definitions
│   ├── claims.yaml                # PersistentVolumeClaims (optional)
│   ├── upgrade.sh                 # Helm deployment script
│   ├── docker-cred.sh             # Docker registry credentials (optional)
│   ├── cloudflare.*.tls.yaml      # TLS certificate secret
│   └── <chart-name>/              # Helm chart directory
│       ├── Chart.yaml             # Helm chart metadata
│       ├── README.md              # Chart documentation
│       └── templates/             # Kubernetes manifests
│           ├── secrets.yaml       # Templated secrets
│           ├── ingress.yaml       # Ingress configuration
│           ├── networkpolicy.yaml # Network policies (optional)
│           ├── *-deployment.yaml  # Deployment specs
│           ├── *-service.yaml     # Service specs
│           └── *-persistentvolumeclaim.yaml
```

## Namespace Conventions

Namespaces use short, hyphenated names:

| Pattern | Example | Projects |
|---------|---------|----------|
| `<app>-ns` | `haka-ns` | hakatime |
| `<app>-n` | `ntm-n` | jira_magic, task_magic |
| `<short>` | `nlb` | live-book |
| `<domain>-wp` | `trl-wp`, `noizu-wp` | WordPress sites |

## Helm Charts

### Chart.yaml

All charts use API version v2 (Helm 3+):

```yaml
name: <chart-name>
description: <description>
version: 0.0.1
apiVersion: v2
keywords:
  - <domain>
  - prod
```

### Origin

Most charts were generated from Docker Compose using **Kompose**:
```bash
kompose -f docker-compose-prod.yml convert --chart
```

## Deployment Scripts

### upgrade.sh Pattern

All projects use a consistent upgrade script:

```bash
#!/usr/bin/env bash

helm upgrade --install <release-name> ./<chart-dir> \
  --namespace <namespace> \
  --set secrets.DATABASE_URL="${DATABASE_URL}" \
  --set secrets.DATABASE_USER="${DATABASE_USER}" \
  --set secrets.DATABASE_NAME="${DATABASE_NAME}" \
  --set secrets.DATABASE_PASSWORD="${DATABASE_PASSWORD}" \
  --set secrets.DATABASE_HOST="${DATABASE_HOST}" \
  --set secrets.DATABASE_PORT="${DATABASE_PORT}" \
  --set secrets.<app-specific>="${APP_SECRET}"
```

**Key Points:**
- Uses `helm upgrade --install` for idempotent deployments
- Secrets passed via `--set` flags from environment variables
- Release name typically matches chart name or `<app>-prod`

### Preferred Pattern (Environment Variables)

The jira_magic, live-book, and blog projects use environment variables:
```bash
--set secrets.DATABASE_PASSWORD="${DATABASE_PASSWORD}"
```

This is more secure than hardcoding (as seen in hakatime's upgrade.sh).

## Service Types

All services use **ClusterIP** (internal-only):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
  namespace: <namespace>
spec:
  type: ClusterIP
  ports:
    - port: 80         # or 5432, 6379, 8080, etc.
      targetPort: 80
  selector:
    io.kompose.service: <service-name>
```

Common services:
- Application server: port 80
- Database (PostgreSQL/TimescaleDB): port 5432
- Redis: port 6379
- Livebook: port 8080

## Ingress Configuration

All projects use NGINX Ingress with TLS:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <app>-ingress
  namespace: <namespace>
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
    - host: <domain>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <service-name>
                port:
                  number: 80
  tls:
    - hosts:
        - <domain>
      secretName: cloudflare-<domain>-tls
```

### TLS Certificate Naming

Pattern: `cloudflare-<domain>-tls`

Examples:
- `cloudflare-hakatime.noizu.com-tls`
- `cloudflare-therobotlives.com-tls`
- `cloudflare-ntm.noizu.com-tls`
- `cloudflare-nb-noizu.com-tls`

## Secrets Management

### Templated Secrets

Secrets use Helm templating with base64 encoding:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <app>-secrets
  namespace: <namespace>
  type: Opaque
data:
  DATABASE_URL: {{ .Values.secrets.DATABASE_URL | b64enc | quote }}
  DATABASE_USER: {{ .Values.secrets.DATABASE_USER | b64enc | quote }}
  DATABASE_NAME: {{ .Values.secrets.DATABASE_NAME | b64enc | quote }}
  DATABASE_PASSWORD: {{ .Values.secrets.DATABASE_PASSWORD | b64enc | quote }}
  DATABASE_HOST: {{ .Values.secrets.DATABASE_HOST | b64enc | quote }}
  DATABASE_PORT: {{ .Values.secrets.DATABASE_PORT | toString | b64enc | quote }}
  SECRET_KEY_BASE: {{ .Values.secrets.SECRET_KEY_BASE | b64enc | quote }}
```

### Common Secret Names

| Project Type | Secret Name |
|--------------|-------------|
| hakatime | `haka-secrets` |
| Elixir apps | `noizu-website-secrets` |
| WordPress | `trl-wp-secrets`, `noizu-wp-secrets` |
| Livebook | `nlb-secrets` |

### Referencing Secrets in Deployments

```yaml
env:
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: <secret-name>
        key: DATABASE_PASSWORD
```

## Persistent Storage

### Storage Class

All projects use **Longhorn** distributed storage:

```yaml
spec:
  storageClassName: longhorn
```

### Volume Naming

Pattern: `/k8-volumes/<domain>/<purpose>`

Examples:
- `/k8-volumes/hakatime.noizu.com/ts-disk`
- `/k8-volumes/ntm.noizu.com/redis-disk`
- `/k8-volumes/nb.noizu.com/live-book-data`
- `/k8-volumes/nb.noizu.com/redis-data`
- `/k8-volumes/nb.noizu.com/ts-data`

### PersistentVolume Template

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: <app>-<purpose>-disk
  namespace: <namespace>
  labels:
    type: local
spec:
  storageClassName: longhorn
  capacity:
    storage: <size>Gi
  accessModes:
    - ReadWriteOnce     # or ReadWriteMany
  hostPath:
    path: "/k8-volumes/<domain>/<purpose>"
```

### Common Volume Sizes

| Purpose | Size |
|---------|------|
| TimescaleDB | 25-50 Gi |
| Redis | 5-25 Gi |
| Application data | 25 Gi |
| WordPress | 10-25 Gi |

## Deployment Patterns

### Standard Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <app-name>
  namespace: <namespace>
  annotations:
    kompose.cmd: kompose -f ../docker-compose-prod.yml convert --chart
    kompose.version: 1.35.0 (9532ceef3)
  labels:
    io.kompose.service: <service-name>
spec:
  replicas: 1
  selector:
    matchLabels:
      io.kompose.service: <service-name>
  template:
    spec:
      containers:
        - name: <container-name>
          image: <registry>/<image>:<tag>
          ports:
            - containerPort: 80
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: <secret-name>
                  key: DATABASE_URL
      restartPolicy: Always
```

### Database Deployment Strategy

Databases use `Recreate` strategy (not RollingUpdate):

```yaml
spec:
  strategy:
    type: Recreate
```

This ensures database consistency during updates.

## Docker Registry Configuration

### Registry Secrets

```bash
kubectl create secret docker-registry ops-registry-secret \
  --docker-server=ops.noizu.com \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  -n <namespace>

kubectl create secret docker-registry docker-registry-secret \
  --docker-server=docker.io \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  -n <namespace>
```

### Patching Service Account

```bash
kubectl patch serviceaccount default \
  -p '{"imagePullSecrets": [{"name": "ops-registry-secret"}, {"name": "docker-registry-secret"}]}' \
  -n <namespace>
```

## Common Images

| Application | Image |
|-------------|-------|
| Hakatime | `ops.noizu.com/hakatime:latest` |
| TimescaleDB | `noizu/timescaledb-ha-with-age:pg16.4-ts2.17.1-all-age1.5.0` |
| Elixir apps | `ops.ntm.noizu.com/noizu-website:release` |
| Livebook | `ghcr.io/livebook-dev/livebook:latest` |
| WordPress | Custom or `wordpress:latest` |

## Pre-requisites

Before deploying any project:

1. **Namespace**: Create the namespace
   ```bash
   kubectl apply -f namespace.yaml
   ```

2. **Volumes**: Create PersistentVolumes
   ```bash
   kubectl apply -f volume.yaml
   ```

3. **TLS Certificate**: Apply Cloudflare TLS secret
   ```bash
   kubectl apply -f cloudflare.*.tls.yaml
   ```

4. **Docker Credentials** (if using private registry):
   ```bash
   ./docker-cred.sh
   ```

5. **Environment Variables**: Export required secrets
   ```bash
   export DATABASE_URL="..."
   export DATABASE_PASSWORD="..."
   # etc.
   ```

6. **Deploy**:
   ```bash
   ./upgrade.sh
   ```

## Cluster Requirements

- Kubernetes v1.19+
- NGINX Ingress Controller
- Longhorn storage provisioner
- Helm 3.x

## Quick Reference

### Useful Commands

```bash
# List all resources in namespace
kubectl get all -n <namespace>

# View pod logs
kubectl logs -f <pod-name> -n <namespace>

# Exec into pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# Check Helm releases
helm list -n <namespace>

# Helm release history
helm history <release-name> -n <namespace>

# Rollback
helm rollback <release-name> <revision> -n <namespace>

# Upgrade/Install
helm upgrade --install <release> ./<chart> -n <namespace> --set ...

# Uninstall
helm uninstall <release-name> -n <namespace>
```
