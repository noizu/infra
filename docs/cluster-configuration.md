# Cluster Configuration

Details about the Kubernetes cluster setup from `~/.kube/config`.

## Clusters

You have two clusters configured:

| Context | Cluster | Server | Purpose |
|---------|---------|--------|---------|
| `local` | local | `https://208.64.36.79:6443` | **Production colo server** |
| `minikube` | minikube | `https://127.0.0.1:58137` | Local development |

## Current Context

```
current-context: minikube
```

**Note:** Your current context is set to `minikube`. To deploy to your colo server, switch to `local`:

```bash
kubectl config use-context local
```

## Production Cluster (local)

- **Server**: `https://208.64.36.79:6443`
- **User**: `cluster-admin`
- **Auth**: Client certificate authentication
  - Certificate: `/var/lib/kubernetes/secrets/cluster-admin.pem`
  - Key: `/var/lib/kubernetes/secrets/cluster-admin-key.pem`
  - CA: `/var/lib/kubernetes/secrets/ca.pem`

This is your colo server where all production deployments should go.

## Development Cluster (minikube)

- **Server**: `https://127.0.0.1:58137`
- **User**: `minikube`
- **Version**: minikube v1.36.0
- **Default namespace**: `default`

Useful for local testing before deploying to production.

## Context Switching

```bash
# View current context
kubectl config current-context

# List all contexts
kubectl config get-contexts

# Switch to production (colo)
kubectl config use-context local

# Switch to development (minikube)
kubectl config use-context minikube

# Verify which cluster you're on
kubectl cluster-info
```

## Deployment Workflow

### Recommended Workflow

1. **Develop & Test locally** (minikube)
   ```bash
   kubectl config use-context minikube
   # Test deployment
   ./upgrade.sh
   kubectl get pods -n <namespace>
   # Verify everything works
   ```

2. **Deploy to production** (local/colo)
   ```bash
   kubectl config use-context local
   # Deploy to colo
   ./upgrade.sh
   kubectl get pods -n <namespace>
   ```

### Safety Check

Before running any deployment, verify your context:

```bash
# Add this to upgrade.sh for safety:
echo "Current context: $(kubectl config current-context)"
echo "Deploying to: $(kubectl cluster-info | head -1)"
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi
```

## Cluster-Specific Notes

### Production (208.64.36.79)

This cluster has:
- NGINX Ingress Controller
- Longhorn storage provisioner
- Host path volumes at `/k8-volumes/`
- External IP for ingress (configure DNS to point here)

### Minikube

For local testing:
```bash
# Start minikube
minikube start

# Enable ingress addon
minikube addons enable ingress

# Enable storage addon
minikube addons enable storage-provisioner

# Get minikube IP for local DNS
minikube ip
```

For testing ingress locally, add to `/etc/hosts`:
```
<minikube-ip>  hakatime.local ntm.local nb.local
```

## Quick Reference

```bash
# Which cluster am I on?
kubectl config current-context
kubectl cluster-info

# List all namespaces
kubectl get ns

# List all pods across namespaces
kubectl get pods -A

# Check node status
kubectl get nodes

# Check storage classes
kubectl get sc

# Check ingress controller
kubectl get pods -n ingress-nginx
```

## Troubleshooting

### Can't connect to cluster

```bash
# Check if certificates exist
ls -la /var/lib/kubernetes/secrets/

# Test connection
kubectl cluster-info

# Check kubeconfig
kubectl config view
```

### Certificate errors

Ensure the certificate paths in kubeconfig are accessible:
- Production: `/var/lib/kubernetes/secrets/`
- Minikube: `~/.minikube/`

### Context not found

```bash
# Re-add context if needed
kubectl config set-context local \
  --cluster=local \
  --user=cluster-admin

kubectl config set-cluster local \
  --server=https://208.64.36.79:6443 \
  --certificate-authority=/var/lib/kubernetes/secrets/ca.pem
```
