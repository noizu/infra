# Quick Start Guide

Fast reference for deploying noizu.com Kubernetes projects.

## Cluster Context

You have two clusters configured:

| Context | Server | Purpose |
|---------|--------|---------|
| `local` | 208.64.36.79:6443 | **Production colo** |
| `minikube` | 127.0.0.1:58137 | Local dev |

```bash
# Check current context
kubectl config current-context

# Switch to production (colo server)
kubectl config use-context local

# Switch to local dev
kubectl config use-context minikube
```

## TL;DR - Deploy Any Project

```bash
cd <project>/kubernetes

# 1. Namespace
kubectl apply -f namespace.yaml

# 2. Volumes
kubectl apply -f volume.yaml
# or: kubectl apply -f volumes.yaml
# or: kubectl apply -f volume-2.yaml

# 3. TLS (if external file)
kubectl apply -f cloudflare.*.tls.yaml

# 4. Docker credentials (if private registry)
./docker-cred.sh

# 5. Set environment variables
export DATABASE_URL="..."
export DATABASE_USER="..."
export DATABASE_PASSWORD="..."
# etc.

# 6. Deploy
./upgrade.sh
```

## Project Quick Reference

### Hakatime

```bash
cd /github/3rd/hakatime/kubernetes
kubectl apply -f namespace.yaml        # haka-ns
kubectl apply -f volume.yaml
kubectl apply -f cloudflare.hakatime.noizu.com.tls.yaml
./docker-cred.sh
./upgrade.sh
```

**Secrets needed**: `POSTGRES_DB`, `POSTGRES_PASSWORD`, `POSTGRES_USER`

### Blog (therobotlives.com)

```bash
cd /github/noizu/blog/wordpress.k8
kubectl apply -f namespace.yaml        # trl-wp
kubectl apply -f noizu.wp.volume.yaml
kubectl apply -f noizu.ts.volume.yaml
kubectl apply -f claims.yaml
# TLS is in helm chart
export DATABASE_URL="..."
export DATABASE_USER="..."
export DATABASE_PASSWORD="..."
export DATABASE_ROOT_PASSWORD="..."
export DATABASE_HOST="..."
export DATABASE_PORT="..."
./upgrade.sh
```

### Jira Magic (ntm.noizu.com)

```bash
cd /github/noizu/jira_magic/kubernetes
kubectl apply -f namespace.yaml        # ntm-n
kubectl apply -f volume.yaml
kubectl apply -f volume-2.yaml
# TLS is in helm chart
export DATABASE_URL="..."
export DATABASE_USER="..."
export DATABASE_NAME="..."
export DATABASE_PASSWORD="..."
export DATABASE_HOST="..."
export DATABASE_PORT="..."
export SECRET_KEY_BASE="..."
./upgrade.sh
```

### Task Magic (ntm.noizu.com)

```bash
cd /github/noizu/task_magic/kubernetes
kubectl apply -f namespace.yaml        # ntm-n
kubectl apply -f volume.yaml
kubectl apply -f volume-2.yaml
# Similar to jira_magic
./upgrade.sh
```

### Live Book (nb.noizu.com)

```bash
cd /github/noizu/live-book
kubectl apply -f namespace.yaml        # nlb
kubectl apply -f volumes.yaml
kubectl apply -f claims.yaml
kubectl apply -f cloudflare.lb.noizu.com.tls.yaml
kubectl apply -f ingress.yaml          # Ingress is separate file
export DATABASE_URL="..."
export DATABASE_USER="..."
export DATABASE_NAME="..."
export DATABASE_PASSWORD="..."
export DATABASE_HOST="..."
export DATABASE_PORT="..."
export REDIS_URI="..."
export LIVEBOOK_SECRET_KEY_BASE="..."
export LIVEBOOK_PASSWORD="..."
export LIVEBOOK_COOKIE="..."
./upgrade.sh
```

### Website Phoenix (noizu.com)

```bash
cd /github/noizu/website/kubernetes/phx.k8
kubectl apply -f namespace.yaml        # noizu-website-namespace
kubectl apply -f volume.yaml
kubectl apply -f volume-2.yaml
kubectl apply -f noizu-redis-data-persistentvolumeclaim.yaml
kubectl apply -f noizu-ts-data-persistentvolumeclaim.yaml
# Set env vars, run upgrade.sh
```

### Website WordPress (noizu.com)

```bash
cd /github/noizu/website/kubernetes/wordpress.k8
kubectl apply -f namespace.yaml        # noizu-wp
kubectl apply -f noizu.wp.volume.yaml
kubectl apply -f noizu.ts.volume.yaml
kubectl apply -f claims.yaml
# Set env vars, run upgrade.sh
```

## Common Environment Variables

| Variable | Description | Used By |
|----------|-------------|---------|
| `DATABASE_URL` | Full connection string | Most apps |
| `DATABASE_USER` | DB username | All |
| `DATABASE_PASSWORD` | DB password | All |
| `DATABASE_NAME` | Database name | Most |
| `DATABASE_HOST` | DB hostname | Most |
| `DATABASE_PORT` | DB port (usually 5432) | Most |
| `DATABASE_ROOT_PASSWORD` | MySQL root password | WordPress |
| `SECRET_KEY_BASE` | Phoenix secret key | Elixir apps |
| `REDIS_URI` | Redis connection string | Live Book |
| `LIVEBOOK_PASSWORD` | Livebook auth | Live Book |
| `LIVEBOOK_SECRET_KEY_BASE` | Livebook secret | Live Book |
| `LIVEBOOK_COOKIE` | Erlang cookie | Live Book |

## Namespace Reference

| Namespace | Projects |
|-----------|----------|
| `haka-ns` | hakatime |
| `trl-wp` | blog (therobotlives.com) |
| `ntm-n` | jira_magic, task_magic |
| `nlb` | live-book |
| `noizu-website-namespace` | website (phoenix) |
| `noizu-wp` | website (wordpress) |

## Common Commands

```bash
# List resources in namespace
kubectl get all -n <namespace>

# Watch pods
kubectl get pods -n <namespace> -w

# Pod logs
kubectl logs -f <pod> -n <namespace>

# Exec into pod
kubectl exec -it <pod> -n <namespace> -- sh

# Helm status
helm list -n <namespace>
helm status <release> -n <namespace>

# Rollback
helm rollback <release> <revision> -n <namespace>

# Delete release
helm uninstall <release> -n <namespace>
```

## Troubleshooting Checklist

1. **Namespace exists?**
   ```bash
   kubectl get ns <namespace>
   ```

2. **Volumes created?**
   ```bash
   kubectl get pv,pvc -n <namespace>
   ```

3. **Secrets exist?**
   ```bash
   kubectl get secrets -n <namespace>
   ```

4. **Pods running?**
   ```bash
   kubectl get pods -n <namespace>
   kubectl describe pod <pod> -n <namespace>
   ```

5. **Services exist?**
   ```bash
   kubectl get svc -n <namespace>
   ```

6. **Ingress configured?**
   ```bash
   kubectl get ingress -n <namespace>
   kubectl describe ingress <ingress> -n <namespace>
   ```

7. **TLS certificate?**
   ```bash
   kubectl get secret cloudflare-*-tls -n <namespace>
   ```

8. **Events?**
   ```bash
   kubectl get events -n <namespace> --sort-by='.lastTimestamp'
   ```
