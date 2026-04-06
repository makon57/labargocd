# Add Cluster Script

The `add-cluster.sh` script automates the creation of new OpenShift cluster configurations for this GitOps repository.

## Usage

```bash
./add-cluster.sh <cluster-name> [--non-interactive]
```

### Parameters

- `<cluster-name>`: Required. The name of the cluster to create. Must be lowercase alphanumeric with hyphens only.
- `--non-interactive`: Optional. Use default values for all configuration options without prompting.

### Examples

```bash
# Interactive mode (prompts for configuration)
./add-cluster.sh prod-cluster-02

# Non-interactive mode (uses defaults)
./add-cluster.sh dev-cluster-03 --non-interactive
```

## What the Script Does

The script creates a complete cluster configuration directory structure under `clusters/<cluster-name>/` with:

1. **kustomization.yaml**: Kustomize overlay that patches the base cluster template with cluster-specific values
2. **patches/install-config.yaml**: OpenShift install configuration with compute, networking, and platform settings  
3. **argocd-application.yaml**: ArgoCD Application resource for GitOps management

## Configuration Options

The script prompts for the following configuration values (or uses defaults in non-interactive mode):

### General Configuration
- **Base domain**: DNS domain for the cluster (default: `openshiftpartnerlabs.com`)
- **AWS region**: Deployment region (default: `us-east-1`)
- **Environment**: Environment tag (default: `development`)
- **ClusterImageSet**: OpenShift version (default: `img4.20.10-x86-64-appsub`)

### Control Plane Configuration
- **Instance type**: EC2 instance type (default: `m8i.2xlarge`)
- **Replicas**: Number of control plane nodes (default: `3`)

### Worker Node Configuration
- **Instance type**: EC2 instance type (default: `m8i.2xlarge`)
- **Replicas**: Number of worker nodes (default: `3`)

### ArgoCD Configuration
- **Project name**: ArgoCD project (default: `cluster-provisioning-argocd`)
- **Git repository URL**: Source repository (default: current repo URL)
- **Target revision**: Git branch/tag (default: `main`)

## Default Values

| Setting | Default Value |
|---------|---------------|
| Base domain | `openshiftpartnerlabs.com` |
| AWS region | `us-east-1` |
| Environment | `development` |
| ClusterImageSet | `img4.20.10-x86-64-appsub` |
| Control plane type | `m8i.2xlarge` |
| Control plane replicas | `3` |
| Worker type | `m8i.2xlarge` |
| Worker replicas | `3` |
| ArgoCD project | `cluster-provisioning-argocd` |

## Generated File Structure

```
clusters/<cluster-name>/
├── kustomization.yaml       # Kustomize overlay with patches
├── patches/
│   └── install-config.yaml  # OpenShift install configuration
└── argocd-application.yaml  # ArgoCD Application resource
```

## Next Steps After Running the Script

The script provides detailed next steps, but here's a summary:

### 1. Create Cluster Namespace
```bash
oc create namespace <cluster-name>
```

### 2. Create Required Secrets

**AWS credentials:**
```bash
oc create secret generic aws-credentials \
  --from-literal=aws_access_key_id=<your-access-key> \
  --from-literal=aws_secret_access_key=<your-secret-key> \
  -n <cluster-name>
```

**Pull secret** (download from console.redhat.com):
```bash
oc create secret generic pull-secret \
  --from-file=.dockerconfigjson=pull-secret.json \
  --type=kubernetes.io/dockerconfigjson \
  -n <cluster-name>
```

**SSH key:**
```bash
ssh-keygen -t rsa -b 4096 -f <cluster-name>-ssh-key -N ""
oc create secret generic <cluster-name>-ssh-key \
  --from-file=ssh-privatekey=<cluster-name>-ssh-key \
  --from-file=ssh-publickey=<cluster-name>-ssh-key.pub \
  --type=kubernetes.io/ssh-auth \
  -n <cluster-name>
```

### 3. Commit and Push
```bash
git add clusters/<cluster-name>/
git commit -m "Add <cluster-name> cluster configuration"
git push origin $(git branch --show-current)
```

### 4. Monitor Provisioning
```bash
oc get clusterdeployment -n <cluster-name> -w
```

## Important Notes

- ⚠️ **Secrets must be created before pushing**: ArgoCD will try to sync immediately after the configuration is pushed
- ⏱️ **Provisioning takes 30-45 minutes**: Be patient during the provisioning process
- 🔒 **Review configuration**: Always review the generated files before committing
- 🔄 **ArgoCD management**: The cluster becomes managed by ArgoCD after first sync

## Troubleshooting

### Script fails with "cluster name invalid"
Ensure the cluster name:
- Contains only lowercase letters, numbers, and hyphens
- Does not start or end with a hyphen
- Does not already exist as a directory

### ArgoCD sync fails immediately
- Verify all required secrets exist in the cluster namespace
- Check that the namespace was created before pushing the configuration
- Ensure ClusterImageSet name exists in the hub cluster

### ClusterDeployment stays in pending state
- Check AWS credentials and permissions
- Verify AWS quotas are sufficient for the requested instance types
- Review Hive operator logs for detailed error messages

## Environment-Specific Recommendations

### Development Clusters
- Use smaller instance types (`m8i.2xlarge`)
- Consider single AZ deployment for cost savings
- Set worker replicas to 0 for truly minimal clusters

### Production Clusters
- Use larger instance types (`m8i.2xlarge` or larger)
- Always use 3 control plane replicas
- Scale worker nodes based on workload requirements
- Consider enabling hibernation for cost management

See [adding-clusters.md](adding-clusters.md) for more detailed cluster configuration guidance.