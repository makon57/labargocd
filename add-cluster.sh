#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_BASE_DOMAIN="openshiftpartnerlabs.com"
DEFAULT_REGION="us-east-1"
DEFAULT_CONTROL_PLANE_TYPE="m8i.2xlarge"
DEFAULT_WORKER_TYPE="m8i.2xlarge"
DEFAULT_CONTROL_PLANE_REPLICAS="3"
DEFAULT_WORKER_REPLICAS="3"
DEFAULT_ENVIRONMENT="development"
DEFAULT_CLUSTERIMAGESET="img4.20.10-x86-64-appsub"
DEFAULT_PROJECT_NAME="cluster-provisioning-argocd"
DEFAULT_REPO_URL="https://github.com/redhat-openshift-partner-labs/labargocd.git"
DEFAULT_TARGET_REVISION="main"

usage() {
    echo "Usage: $0 <cluster-name> [--non-interactive]"
    echo
    echo "This script creates a new cluster configuration in the clusters/ directory."
    echo "It will prompt you for configuration options or use defaults."
    echo
    echo "Options:"
    echo "  --non-interactive    Use all default values without prompting"
    echo
    echo "Example:"
    echo "  $0 my-new-cluster"
    echo "  $0 my-new-cluster --non-interactive"
    echo
}

prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    echo -e "${BLUE}$prompt${NC} [${YELLOW}$default${NC}]: "
    read -r user_input
    if [[ -z "$user_input" ]]; then
        eval "$var_name='$default'"
    else
        eval "$var_name='$user_input'"
    fi
}

validate_cluster_name() {
    local name="$1"

    # Check if name is lowercase alphanumeric with hyphens only
    if [[ ! "$name" =~ ^[a-z0-9-]+$ ]]; then
        echo -e "${RED}Error: Cluster name must be lowercase alphanumeric with hyphens only${NC}"
        exit 1
    fi

    # Check if name doesn't start or end with hyphen
    if [[ "$name" =~ ^- ]] || [[ "$name" =~ -$ ]]; then
        echo -e "${RED}Error: Cluster name cannot start or end with a hyphen${NC}"
        exit 1
    fi

    # Check if directory already exists
    if [[ -d "clusters/$name" ]]; then
        echo -e "${RED}Error: Cluster directory 'clusters/$name' already exists${NC}"
        exit 1
    fi
}

create_kustomization_yaml() {
    local cluster_name="$1"
    local base_domain="$2"
    local region="$3"
    local clusterimageset="$4"
    local control_plane_type="$5"
    local worker_type="$6"
    local control_plane_replicas="$7"
    local worker_replicas="$8"
    local environment="$9"

    cat > "clusters/$cluster_name/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: $cluster_name

resources:
  - ../../cluster-templates/aws-ha/base

patches:
  # Install config secret content - must come before rename
  - path: patches/install-config.yaml

  # Rename ClusterDeployment
  - target:
      kind: ClusterDeployment
      name: cluster-placeholder
    patch: |-
      - op: replace
        path: /metadata/name
        value: $cluster_name
      - op: replace
        path: /spec/clusterName
        value: $cluster_name
      - op: replace
        path: /spec/baseDomain
        value: $base_domain
      - op: replace
        path: /spec/platform/aws/region
        value: $region
      - op: replace
        path: /spec/provisioning/imageSetRef/name
        value: $clusterimageset
      - op: replace
        path: /spec/provisioning/installConfigSecretRef/name
        value: $cluster_name-install-config
      - op: replace
        path: /spec/provisioning/sshPrivateKeySecretRef/name
        value: $cluster_name-ssh-key
      - op: remove
        path: /spec/provisioning/manifestsConfigMapRef

  # Rename MachinePool
  - target:
      kind: MachinePool
      name: cluster-placeholder-worker
    patch: |-
      - op: replace
        path: /metadata/name
        value: $cluster_name-worker
      - op: replace
        path: /spec/clusterDeploymentRef/name
        value: $cluster_name
      - op: replace
        path: /spec/replicas
        value: $worker_replicas
      - op: replace
        path: /spec/platform/aws/type
        value: $worker_type

  # Rename ManagedCluster
  - target:
      kind: ManagedCluster
      name: cluster-placeholder
    patch: |-
      - op: replace
        path: /metadata/name
        value: $cluster_name
      - op: add
        path: /metadata/labels/environment
        value: $environment

  # Rename KlusterletAddonConfig
  - target:
      kind: KlusterletAddonConfig
      name: cluster-placeholder
    patch: |-
      - op: replace
        path: /metadata/name
        value: $cluster_name
      - op: replace
        path: /spec/clusterName
        value: $cluster_name
      - op: replace
        path: /spec/clusterNamespace
        value: $cluster_name

  # Rename install-config Secret
  - target:
      kind: Secret
      name: cluster-placeholder-install-config
    patch: |-
      - op: replace
        path: /metadata/name
        value: $cluster_name-install-config

  # Fix AccessKey namespace for secret (if using Crossplane)
  - target:
      group: iam.aws.upbound.io
      kind: AccessKey
      name: ocp-installer-access-key
    patch: |-
      - op: replace
        path: /spec/writeConnectionSecretToRef/namespace
        value: $cluster_name
EOF
}

create_install_config_yaml() {
    local cluster_name="$1"
    local base_domain="$2"
    local region="$3"
    local control_plane_type="$4"
    local worker_type="$5"
    local control_plane_replicas="$6"
    local worker_replicas="$7"

    cat > "clusters/$cluster_name/patches/install-config.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: cluster-placeholder-install-config
  namespace: cluster-placeholder
stringData:
  install-config.yaml: |
    apiVersion: v1
    baseDomain: $base_domain
    metadata:
      name: $cluster_name

    controlPlane:
      name: master
      platform:
        aws:
          type: $control_plane_type
          rootVolume:
            iops: 4000
            size: 120
            type: gp3
          zones:
            - ${region}a
            - ${region}b
            - ${region}c
      replicas: $control_plane_replicas

    compute:
      - name: worker
        platform:
          aws:
            type: $worker_type
            rootVolume:
              iops: 2000
              size: 100
              type: gp3
            zones:
              - ${region}a
              - ${region}b
              - ${region}c
        replicas: $worker_replicas

    networking:
      clusterNetwork:
        - cidr: 10.128.0.0/14
          hostPrefix: 23
      machineNetwork:
        - cidr: 10.0.0.0/16
      serviceNetwork:
        - 172.30.0.0/16
      networkType: OVNKubernetes

    platform:
      aws:
        region: $region

    fips: false
    publish: External
EOF
}

create_argocd_application_yaml() {
    local cluster_name="$1"
    local project_name="$2"
    local repo_url="$3"
    local target_revision="$4"

    cat > "clusters/$cluster_name/argocd-application.yaml" << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $cluster_name
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: $project_name
  source:
    repoURL: $repo_url
    targetRevision: $target_revision
    path: clusters/$cluster_name
  destination:
    server: https://kubernetes.default.svc
    namespace: $cluster_name
  syncPolicy:
    automated:
      prune: false
      selfHeal: false  # CRITICAL: Must be false to prevent accidental cluster deletion
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
  ignoreDifferences:
    - group: hive.openshift.io
      kind: ClusterDeployment
      jsonPointers:
        - /status
        - /spec/clusterMetadata
        - /spec/installed
    - group: cluster.open-cluster-management.io
      kind: ManagedCluster
      jsonPointers:
        - /status
        - /spec/managedClusterClientConfigs
EOF
}

print_next_steps() {
    local cluster_name="$1"

    echo
    echo -e "${GREEN}✅ Cluster configuration created successfully!${NC}"
    echo
    echo -e "${YELLOW}📋 Next steps:${NC}"
    echo
    echo "1. Create the cluster namespace:"
    echo -e "   ${BLUE}oc create namespace $cluster_name${NC}"
    echo
    echo "2. Create required secrets in the cluster namespace:"
    echo
    echo "   📍 AWS credentials:"
    echo -e "   ${BLUE}oc create secret generic aws-credentials \\${NC}"
    echo -e "   ${BLUE}     --from-literal=aws_access_key_id=<your-access-key> \\${NC}"
    echo -e "   ${BLUE}     --from-literal=aws_secret_access_key=<your-secret-key> \\${NC}"
    echo -e "   ${BLUE}     -n $cluster_name${NC}"
    echo
    echo "   📍 Pull secret (download from console.redhat.com):"
    echo -e "   ${BLUE}oc create secret generic pull-secret \\${NC}"
    echo -e "   ${BLUE}     --from-file=.dockerconfigjson=pull-secret.json \\${NC}"
    echo -e "   ${BLUE}     --type=kubernetes.io/dockerconfigjson \\${NC}"
    echo -e "   ${BLUE}     -n $cluster_name${NC}"
    echo
    echo "   📍 SSH key:"
    echo -e "   ${BLUE}ssh-keygen -t rsa -b 4096 -f $cluster_name-ssh-key -N \"\"${NC}"
    echo -e "   ${BLUE}oc create secret generic $cluster_name-ssh-key \\${NC}"
    echo -e "   ${BLUE}     --from-file=ssh-privatekey=$cluster_name-ssh-key \\${NC}"
    echo -e "   ${BLUE}     --from-file=ssh-publickey=$cluster_name-ssh-key.pub \\${NC}"
    echo -e "   ${BLUE}     --type=kubernetes.io/ssh-auth \\${NC}"
    echo -e "   ${BLUE}     -n $cluster_name${NC}"
    echo
    echo "3. Commit and push the configuration:"
    echo -e "   ${BLUE}git add clusters/$cluster_name/${NC}"
    echo -e "   ${BLUE}git commit -m \"Add $cluster_name cluster configuration\"${NC}"
    echo -e "   ${BLUE}git push origin \$(git branch --show-current)${NC}"
    echo
    echo "4. Monitor the provisioning process:"
    echo -e "   ${BLUE}oc get clusterdeployment -n $cluster_name -w${NC}"
    echo
    echo -e "${YELLOW}⚠️  Important notes:${NC}"
    echo "• Provisioning takes 30-45 minutes"
    echo "• Make sure all secrets are created before pushing the configuration"
    echo "• Review the generated configuration files before committing"
    echo "• The cluster will be managed by ArgoCD after the first sync"
    echo
}

main() {
    # Handle help option
    if [[ $# -ge 1 ]] && [[ "$1" == "--help" || "$1" == "-h" ]]; then
        usage
        exit 0
    fi

    # Check if cluster name is provided
    if [[ $# -lt 1 ]] || [[ $# -gt 2 ]]; then
        usage
        exit 1
    fi

    local cluster_name="$1"
    local non_interactive=false

    if [[ $# -eq 2 ]] && [[ "$2" == "--non-interactive" ]]; then
        non_interactive=true
    elif [[ $# -eq 2 ]]; then
        echo -e "${RED}Error: Invalid option '$2'${NC}"
        usage
        exit 1
    fi

    echo -e "${GREEN}🚀 OpenShift Cluster Configuration Generator${NC}"
    echo "=============================================="
    echo

    # Validate cluster name
    echo -e "${BLUE}Validating cluster name...${NC}"
    validate_cluster_name "$cluster_name"
    echo -e "${GREEN}✅ Cluster name '$cluster_name' is valid${NC}"
    echo

    # Gather configuration
    if [[ "$non_interactive" == true ]]; then
        echo -e "${YELLOW}📝 Using default configuration values...${NC}"
        base_domain="$DEFAULT_BASE_DOMAIN"
        region="$DEFAULT_REGION"
        environment="$DEFAULT_ENVIRONMENT"
        clusterimageset="$DEFAULT_CLUSTERIMAGESET"
        control_plane_type="$DEFAULT_CONTROL_PLANE_TYPE"
        control_plane_replicas="$DEFAULT_CONTROL_PLANE_REPLICAS"
        worker_type="$DEFAULT_WORKER_TYPE"
        worker_replicas="$DEFAULT_WORKER_REPLICAS"
        project_name="$DEFAULT_PROJECT_NAME"
        repo_url="$DEFAULT_REPO_URL"
        target_revision="$DEFAULT_TARGET_REVISION"
    else
        echo -e "${YELLOW}📝 Please provide cluster configuration (press Enter for defaults):${NC}"
        echo

        prompt_with_default "Base domain" "$DEFAULT_BASE_DOMAIN" "base_domain"
        prompt_with_default "AWS region" "$DEFAULT_REGION" "region"
        prompt_with_default "Environment (development/staging/production)" "$DEFAULT_ENVIRONMENT" "environment"
        prompt_with_default "ClusterImageSet name" "$DEFAULT_CLUSTERIMAGESET" "clusterimageset"

        echo
        echo -e "${YELLOW}🖥️  Control Plane Configuration:${NC}"
        prompt_with_default "Control plane instance type" "$DEFAULT_CONTROL_PLANE_TYPE" "control_plane_type"
        prompt_with_default "Control plane replicas" "$DEFAULT_CONTROL_PLANE_REPLICAS" "control_plane_replicas"

        echo
        echo -e "${YELLOW}👷 Worker Node Configuration:${NC}"
        prompt_with_default "Worker instance type" "$DEFAULT_WORKER_TYPE" "worker_type"
        prompt_with_default "Worker replicas" "$DEFAULT_WORKER_REPLICAS" "worker_replicas"

        echo
        echo -e "${YELLOW}🔧 ArgoCD Configuration:${NC}"
        prompt_with_default "ArgoCD project name" "$DEFAULT_PROJECT_NAME" "project_name"
        prompt_with_default "Git repository URL" "$DEFAULT_REPO_URL" "repo_url"
        prompt_with_default "Git target revision" "$DEFAULT_TARGET_REVISION" "target_revision"
    fi

    # Create directory structure
    echo
    echo -e "${BLUE}📁 Creating cluster directory structure...${NC}"
    mkdir -p "clusters/$cluster_name/patches"

    # Create configuration files
    echo -e "${BLUE}📄 Generating kustomization.yaml...${NC}"
    create_kustomization_yaml "$cluster_name" "$base_domain" "$region" "$clusterimageset" \
        "$control_plane_type" "$worker_type" "$control_plane_replicas" "$worker_replicas" "$environment"

    echo -e "${BLUE}📄 Generating install-config.yaml...${NC}"
    create_install_config_yaml "$cluster_name" "$base_domain" "$region" \
        "$control_plane_type" "$worker_type" "$control_plane_replicas" "$worker_replicas"

    echo -e "${BLUE}📄 Generating argocd-application.yaml...${NC}"
    create_argocd_application_yaml "$cluster_name" "$project_name" "$repo_url" "$target_revision"

    # Print summary and next steps
    print_next_steps "$cluster_name"
}

# Run main function
main "$@"