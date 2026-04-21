# User Guide: Provisioning Your First OpenShift Cluster

This guide walks you through provisioning a new OpenShift cluster using the existing ArgoCD/GitOps infrastructure.

## Prerequisites

Before you begin, ensure you have:

- ✅ Access to the hub cluster at [console-openshift-console.apps.prod.openshiftpartnerlabs.com](https://console-openshift-console.apps.prod.openshiftpartnerlabs.com/dashboards)
- ✅ `oc` CLI installed and configured
- ✅ Git access to this repository
- ✅ A Red Hat pull secret (download from [console.redhat.com](https://console.redhat.com))

## Step 1: Generate Cluster Configuration

Use the `add-cluster.sh` script to generate your cluster configuration:

```bash
./add-cluster.sh my-cluster-name
```

The script will prompt you for configuration options like:
- Base domain (default: `openshiftpartnerlabs.com`)
- AWS region (default: `us-east-1`)
- Instance types and replica counts
- Environment label

For defaults, you can run:
```bash
./add-cluster.sh my-cluster-name --non-interactive
```

## Step 2: Create Required Secrets

After generating the configuration, create the required secrets in the hub cluster:

### 1. Create the cluster namespace
```bash
oc create namespace my-cluster-name
```

### 2. Create the pull secret
Download your pull secret from [console.redhat.com](https://console.redhat.com) and save it as `pull-secret.json`, then:

```bash
oc create secret generic pull-secret \
     --from-file=.dockerconfigjson=pull-secret.json \
     --type=kubernetes.io/dockerconfigjson \
     -n my-cluster-name
```

### 3. Create an SSH key for cluster access
```bash
ssh-keygen -t rsa -b 4096 -f my-cluster-name-ssh-key -N ""
oc create secret generic my-cluster-name-ssh-key \
     --from-file=ssh-privatekey=my-cluster-name-ssh-key \
     --from-file=ssh-publickey=my-cluster-name-ssh-key.pub \
     --type=kubernetes.io/ssh-auth \
     -n my-cluster-name
```

**Important:** Keep your private key file (`my-cluster-name-ssh-key`) safe - you'll need it to access your cluster nodes.

## Step 3: Create a Pull Request

Commit and push your configuration:

```bash
git add clusters/my-cluster-name/
git commit -m "[PROVISION] Add my-cluster-name cluster configuration"
git push origin $(git branch --show-current)
```

Open a pull request against the `main` branch. Once merged, ArgoCD will automatically start provisioning your cluster.

## Step 4: Monitor Provisioning

Watch the provisioning progress:

```bash
# Monitor the cluster deployment
oc get clusterdeployment -n my-cluster-name -w

# Check ArgoCD application status
oc get application my-cluster-name -n openshift-gitops

# View detailed logs if needed
oc logs -f deployment/cluster-manager-deployment -n open-cluster-management
```

## Step 5: Access Your New Cluster

Once provisioning completes (30-45 minutes), get your cluster's admin credentials:

```bash
# Extract the admin kubeconfig
oc extract secret/my-cluster-name-admin-kubeconfig -n my-cluster-name --to=./

# Extract the admin password
oc extract secret/my-cluster-name-admin-password -n my-cluster-name --to=./

# Use the kubeconfig to access your cluster
export KUBECONFIG=./kubeconfig
oc get nodes

# Or access the web console
echo "Console URL: https://console-openshift-console.apps.my-cluster-name.openshiftpartnerlabs.com"
echo "Username: kubeadmin"
echo "Password: $(cat password)"
```

## Alternative: Manual Configuration

If you prefer to create the manifests manually instead of using the script:

1. Copy the `cluster-templates/aws-ha/base` template
2. Create your cluster directory: `mkdir -p clusters/my-cluster-name/patches`
3. Customize the `kustomization.yaml` with your cluster-specific values
4. Create the `patches/install-config.yaml` with your OpenShift install configuration
5. Create the `argocd-application.yaml` to register with ArgoCD
6. Follow steps 2-5 above for secrets and PR creation

## Troubleshooting

### Common Issues

**Provisioning stuck or failed:**
```bash
# Check cluster deployment status and conditions
oc describe clusterdeployment my-cluster-name -n my-cluster-name

# Check Hive logs
oc logs -l app=hive-controllers -n hive --tail=100
```

**ArgoCD sync issues:**
```bash
# Check application health
oc describe application my-cluster-name -n openshift-gitops

# Manual sync if needed
argocd app sync my-cluster-name
```

**Secret creation errors:**
- Ensure you're connected to the hub cluster
- Verify the namespace exists before creating secrets
- Check that your pull secret JSON is valid

### Getting Help

- Check the ArgoCD dashboard in the hub cluster console
- View cluster provisioning logs in the Hive operator namespace
- Review the generated manifests in `clusters/my-cluster-name/` before committing

## Important Notes

- 🕒 **Provisioning time**: Expect 30-45 minutes for a complete cluster deployment
- 🔐 **AWS credentials**: Automatically managed by Crossplane - no manual setup needed
- 🔄 **GitOps**: Once your PR is merged, everything is managed through Git - avoid manual changes
- 🏗️ **Infrastructure**: All supporting infrastructure (VPC, DNS, etc.) is created automatically
- 💰 **Costs**: Remember to deprovision clusters when no longer needed to avoid AWS charges

## Cleanup

To deprovision a cluster, remove its directory from the repo and merge the PR:

```bash
git rm -r clusters/my-cluster-name/
git commit -m "[DEPROVISION] Remove my-cluster-name cluster"
```

ArgoCD will automatically handle the cleanup of AWS resources.