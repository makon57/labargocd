# Crossplane AWS IAM Resources

This folder contains Crossplane manifests to provision AWS IAM credentials for an OpenShift cluster installer user.

## Quick Start

Complete these steps in order to set up Crossplane with ArgoCD:

1. Install Crossplane via Helm
2. Create `aws-credentials` secret in `crossplane-system` namespace
3. Grant ArgoCD cluster-level permissions for Crossplane resources
4. Create cluster namespace and grant ArgoCD admin permissions in it
5. Apply bootstrap manifests (`kubectl apply -f bootstrap/crossplane-provider.yaml`)
6. Grant SCC permissions to provider pods (OpenShift only)
7. Verify ProviderConfig and Provider are healthy

See [Prerequisites](#prerequisites) section below for detailed commands.

## Resource Inventory

| File | Kind | Name | Purpose |
|------|------|------|---------|
| `provider.yaml` | `Provider` + `ProviderConfig` | `provider-aws-iam` / `default` | Installs the Upbound AWS IAM provider (`v1.7.0` - compatible with Crossplane 2.2.0) and binds it to the `aws-credentials` secret in `crossplane-system` namespace |
| `iam-user.yaml` | `User` | `ocp-installer` | Creates an AWS IAM user for the OpenShift installer |
| `iam-policy.yaml` | `Policy` | `OpenShift4InstallerPolicy` | IAM policy with EC2, ELB, autoscaling, IAM, S3, Route53, and service-quotas permissions required for OCP 4.20 installation |
| `iam-attachment.yaml` | `UserPolicyAttachment` | `ocp-installer-policy-attachment` | Attaches `OpenShift4InstallerPolicy` to the `ocp-installer` user |
| `iam-access-key.yaml` | `AccessKey` | `ocp-installer-access-key` | Generates an AWS access key and writes the credentials to the `aws-credentials-raw` secret with keys: `username` (access key ID) and `password` (secret access key) |
| `credentials-transformer-job.yaml` | `Job` + RBAC | `aws-credentials-transformer` | Transforms Crossplane credentials format to Hive-compatible format with keys: `aws_access_key_id` and `aws_secret_access_key` |

## Prerequisites

Complete these steps **in order** before applying the bootstrap manifests.

### 1. Install Crossplane on OpenShift

For **OpenShift**, use these commands to install with proper security contexts:

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update
helm upgrade --install crossplane \
  crossplane-stable/crossplane \
  --namespace crossplane-system \
  --version 2.2.0 \
  --set args='{--enable-usages}' \
  --set securityContextCrossplane.runAsUser=null \
  --set securityContextCrossplane.runAsGroup=null \
  --set securityContextRBACManager.runAsUser=null \
  --set securityContextRBACManager.runAsGroup=null \
  --create-namespace
```

**Note:** The `null` security context settings allow OpenShift to assign UIDs dynamically, which is required for OpenShift's security model.

See the [official Crossplane installation docs](https://docs.crossplane.io/latest/get-started/install/) for more options.

### 2. Create the AWS credentials secret

This secret is used by the `ProviderConfig` to authenticate with AWS:

```bash
kubectl create secret generic aws-credentials \
  -n crossplane-system \
  --from-literal=creds="[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY"
```

**Important:** The secret key must be named `creds` (not `credentials`) to match the ProviderConfig in `bootstrap/crossplane-provider.yaml`.

### 3. Grant ArgoCD permissions for Crossplane resources

ArgoCD needs cluster-level permissions to create and manage Crossplane IAM resources:

```bash
kubectl create clusterrolebinding argocd-crossplane-resources \
  --clusterrole=crossplane-edit \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller
```

### 4. Grant ArgoCD admin permissions in cluster namespaces

For each cluster namespace (e.g., `dev-cluster-01`), ArgoCD needs admin permissions to create ServiceAccounts, Jobs, and other resources:

```bash
# Replace <namespace> with your cluster namespace (e.g., dev-cluster-01)
kubectl create namespace <namespace>
kubectl create rolebinding argocd-admin \
  -n <namespace> \
  --clusterrole=admin \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller
```

**Note:** ArgoCD's `CreateNamespace=true` syncOption will create the namespace, but won't automatically grant itself permissions in it.

### 5. Apply bootstrap and wait for provider installation

Now you can apply the bootstrap manifests:

```bash
kubectl apply -f bootstrap/crossplane-provider.yaml

# Wait for provider to be installed
kubectl wait provider provider-aws-iam --for=condition=Installed --timeout=120s
```

### 6. Grant Security Context Constraints (OpenShift only)

After the provider is installed, grant the necessary SCCs to allow provider pods to run:

```bash
# Get the provider revision service account name
PROVIDER_SA=$(kubectl get deployment -n crossplane-system -o name | grep provider-aws-iam | sed 's/deployment.apps\///')

# Grant privileged SCC
oc adm policy add-scc-to-user privileged -z ${PROVIDER_SA} -n crossplane-system

# Restart the provider deployment to pick up new permissions
kubectl rollout restart deployment ${PROVIDER_SA} -n crossplane-system
```

Repeat for the `upbound-provider-family-aws` provider if using the Upbound provider family.

### 7. Verify the setup

Check that the ProviderConfig is ready:

```bash
kubectl get providerconfig
# Should show: NAME=default, AGE=<time>

kubectl get provider
# Should show: provider-aws-iam INSTALLED=True HEALTHY=True
```

## Usage

After completing all prerequisites, the Crossplane resources are automatically created by ArgoCD when you deploy a cluster.

### How it works

When ArgoCD syncs a cluster application (e.g., `dev-cluster-01`), it applies these Crossplane resources in order:

1. **IAM User** (`iam-user.yaml`) - sync-wave: `-4`
2. **IAM Policy** (`iam-policy.yaml`) - sync-wave: `-3`
3. **Policy Attachment** (`iam-attachment.yaml`) - sync-wave: `-3`
4. **Access Key** (`iam-access-key.yaml`) - sync-wave: `-2`
5. **Credentials Transformer Job** (`credentials-transformer-job.yaml`) - sync-wave: `-1`

### Verify the resources

Check that all Crossplane IAM resources are synced and ready:

```bash
kubectl get user,policy,userpolicyattachment,accesskey \
  -l app.kubernetes.io/part-of=ocp-installer

# Expected output:
# NAME                                    SYNCED   READY   EXTERNAL-NAME
# user.iam.aws.upbound.io/ocp-installer   True     True    ocp-installer
#
# NAME                                                    SYNCED   READY   EXTERNAL-NAME
# policy.iam.aws.upbound.io/openshift4-installer-policy   True     True    openshift4-installer-policy
#
# NAME                                                                      SYNCED   READY   EXTERNAL-NAME
# userpolicyattachment.iam.aws.upbound.io/ocp-installer-policy-attachment   True     True    ocp-installer-...
#
# NAME                                                    SYNCED   READY   EXTERNAL-NAME
# accesskey.iam.aws.upbound.io/ocp-installer-access-key   True     True    AKIA...
```

All resources should show `SYNCED: True` and `READY: True`.

## Retrieving the Generated Credentials

Once the `AccessKey` resource is ready, Crossplane writes the generated AWS credentials to a secret:

```bash
# Crossplane-generated secret (raw format)
kubectl get secret aws-credentials-raw -n <namespace> \
  -o jsonpath='{.data}' | jq 'map_values(@base64d)'
```

The Crossplane secret contains:
- `username` - AWS access key ID
- `password` - AWS secret access key

### Credentials Transformer

The `credentials-transformer-job.yaml` automatically converts the Crossplane credentials format to Hive-compatible format:

**Input (Crossplane format):** `aws-credentials-raw` secret with `username` and `password` keys

**Output (Hive format):** `aws-credentials` secret with `aws_access_key_id` and `aws_secret_access_key` keys

```bash
# Hive-compatible credentials secret
kubectl get secret aws-credentials -n <namespace> \
  -o jsonpath='{.data}' | jq 'map_values(@base64d)'
```

## Cleanup

To delete all IAM resources, apply in reverse order to respect dependencies (access key and attachment before policy and user):

```bash
kubectl delete -f crossplane/iam-access-key.yaml \
               -f crossplane/iam-attachment.yaml \
               -f crossplane/iam-policy.yaml \
               -f crossplane/iam-user.yaml
```

Crossplane will delete the corresponding AWS resources before removing the Kubernetes objects. To also remove the provider:

```bash
kubectl delete -f crossplane/provider.yaml
```

## Troubleshooting

### ArgoCD cannot create Crossplane resources (RBAC error)

**Error:**
```
users.iam.aws.upbound.io is forbidden: User "system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller" cannot create resource "users" in API group "iam.aws.upbound.io" at the cluster scope
```

**Solution:** Grant ArgoCD cluster-level permissions for Crossplane resources:

```bash
kubectl create clusterrolebinding argocd-crossplane-resources \
  --clusterrole=crossplane-edit \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller
```

### ArgoCD cannot create resources in cluster namespace

**Error:**
```
serviceaccounts is forbidden: User "system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller" cannot create resource "serviceaccounts" in API group "" in the namespace "dev-cluster-01"
```

**Solution:** Grant ArgoCD admin permissions in the cluster namespace:

```bash
kubectl create rolebinding argocd-admin \
  -n dev-cluster-01 \
  --clusterrole=admin \
  --serviceaccount=openshift-gitops:openshift-gitops-argocd-application-controller
```

Replace `dev-cluster-01` with your cluster namespace.

### Crossplane resources stuck with "static credentials are empty"

**Error:**
```
cannot retrieve the AWS credentials: failed to refresh cached credentials, static credentials are empty
```

**Causes:**
1. The secret key name doesn't match the ProviderConfig
2. The credentials are malformed
3. The provider hasn't restarted after ProviderConfig changes

**Solutions:**

1. Verify the secret has the correct key name (`creds`):
```bash
kubectl get secret aws-credentials -n crossplane-system -o jsonpath='{.data}' | jq 'keys'
# Should show: ["aws_access_key_id", "aws_secret_access_key", "creds"]
```

2. Verify the credentials format:
```bash
kubectl get secret aws-credentials -n crossplane-system -o jsonpath='{.data.creds}' | base64 -d
# Should show:
# [default]
# aws_access_key_id = AKIA...
# aws_secret_access_key = ...
```

3. Restart the provider to pick up the ProviderConfig:
```bash
PROVIDER_SA=$(kubectl get deployment -n crossplane-system -o name | grep provider-aws-iam | sed 's/deployment.apps\///')
kubectl rollout restart deployment ${PROVIDER_SA} -n crossplane-system
```

### Provider pods not starting on OpenShift

**Error:**
```
pods "provider-aws-iam-xxx" is forbidden: unable to validate against any security context constraint
```

**Solution:** Grant privileged SCC to the provider service account:

```bash
PROVIDER_SA=$(kubectl get deployment -n crossplane-system -o name | grep provider-aws-iam | sed 's/deployment.apps\///')
oc adm policy add-scc-to-user privileged -z ${PROVIDER_SA} -n crossplane-system
kubectl rollout restart deployment ${PROVIDER_SA} -n crossplane-system
```

### ProviderConfig not found errors

**Error:**
```
cannot get referenced ProviderConfig: "default": ProviderConfig.aws.upbound.io "default" not found
```

**Solution:** Ensure the ProviderConfig exists cluster-wide:
```bash
kubectl get providerconfig
```

If missing, apply the provider configuration from the bootstrap directory:
```bash
kubectl apply -f bootstrap/crossplane-provider.yaml
```

### Credentials transformer fails

If the transformer job shows errors about missing keys:

**Solution:** The job expects Crossplane secret keys named `username` and `password`. Verify the AccessKey resource is creating the secret correctly:

```bash
kubectl get secret aws-credentials-raw -n <namespace> -o yaml
```
