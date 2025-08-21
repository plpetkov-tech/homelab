#!/bin/bash

# Flux v2 Bootstrap Script for Homelab 

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_info "🚀 Starting Flux v2 Bootstrap for Homelab..."

# Check if flux CLI is installed
if ! command -v flux &> /dev/null; then
    log_error "Flux CLI not found. Please install it first:"
    echo "curl -s https://fluxcd.io/install.sh | sudo bash"
    exit 1
fi

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    log_error "kubectl is not configured or cluster is not accessible"
    exit 1
fi

# Show current context and ask for confirmation
CURRENT_CONTEXT=$(kubectl config current-context)
log_warning "Current Kubernetes context: $CURRENT_CONTEXT"
read -p "Are you sure you want to bootstrap Flux on this cluster? (y/N): " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Aborted by user."
    exit 0
fi

# Check if SOPS and age are installed
if ! command -v sops &> /dev/null; then
    log_error "SOPS not found. Please install it first:"
    echo "See SOPS-SETUP.md for installation instructions"
    exit 1
fi

if ! command -v age &> /dev/null; then
    log_error "age not found. Please install it first:"
    echo "See SOPS-SETUP.md for installation instructions"
    exit 1
fi

log_success "Prerequisites check passed"

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Set variables
GITHUB_USER="plpetkov-tech"
GITHUB_REPO="homelab"
GITHUB_TOKEN="${GITHUB_TOKEN}"
CLUSTER_PATH="$REPO_ROOT/flux/clusters/homelab"

if [ -z "$GITHUB_TOKEN" ]; then
    log_error "GITHUB_TOKEN environment variable is required"
    echo "Please set it with: export GITHUB_TOKEN=<your-token>"
    exit 1
fi

# Check if age key exists
if [ ! -f "$REPO_ROOT/age.agekey" ]; then
    log_error "age.agekey not found. Please generate it first:"
    echo "age-keygen -o age.agekey"
    echo "Then update .sops.yaml with your public key and encrypt secrets"
    echo "See SOPS-SETUP.md for detailed instructions"
    exit 1
fi

# Verify SOPS can decrypt (test with a known encrypted file)
log_info "Verifying SOPS can decrypt secrets..."
export SOPS_AGE_KEY_FILE="$REPO_ROOT/age.agekey"
if ! sops -d "$REPO_ROOT/flux/infrastructure/base/security-policies/cloudflare-secret.yaml" > /dev/null 2>&1; then
    log_error "SOPS decryption test failed. Please check your age.agekey file."
    exit 1
fi
log_success "SOPS decryption test passed"

log_info "🔧 Bootstrapping Flux v2 with GitHub repository..."

# Bootstrap Flux
if flux bootstrap github \
  --components-extra=image-reflector-controller,image-automation-controller \
  --owner=$GITHUB_USER \
  --repository=$GITHUB_REPO \
  --branch=main \
  --path=$CLUSTER_PATH \
  --personal \
  --token-auth; then
    log_success "Flux v2 bootstrap completed!"
else
    log_error "Flux bootstrap failed!"
    exit 1
fi

log_info "🔐 Setting up SOPS for secret management..."

# Create SOPS secret
if kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey="$REPO_ROOT/age.agekey" \
  --dry-run=client -o yaml | kubectl apply -f -; then
    log_success "SOPS secret created successfully"
else
    log_error "Failed to create SOPS secret"
    exit 1
fi

log_info "🏗️ Validating infrastructure before GitOps deployment..."
if ! "$SCRIPT_DIR/validate-infrastructure.sh"; then
    log_error "Infrastructure validation failed. Please fix issues before proceeding."
    exit 1
fi

log_info "🔍 Waiting for Flux controllers to be ready..."
kubectl wait --for=condition=Ready pod -l app -n flux-system --timeout=300s

log_info "🔍 Checking Flux system status..."
kubectl get pods -n flux-system

# Graduated deployment validation with health checks
validate_kustomization() {
    local kustomization_name=$1
    local timeout=${2:-300}
    
    log_info "⏳ Waiting for kustomization '$kustomization_name' to be ready..."
    
    for i in $(seq 1 $((timeout/10))); do
        if kubectl get kustomization "$kustomization_name" -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
            log_success "✅ Kustomization '$kustomization_name' is ready"
            return 0
        fi
        
        if kubectl get kustomization "$kustomization_name" -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null | grep -q "BuildFailed\|HealthCheckFailed"; then
            log_error "❌ Kustomization '$kustomization_name' failed"
            kubectl get kustomization "$kustomization_name" -n flux-system -o yaml
            return 1
        fi
        
        log_info "⏳ Still waiting for '$kustomization_name'... (${i}0s/${timeout}s)"
        sleep 10
    done
    
    log_error "❌ Timeout waiting for kustomization '$kustomization_name'"
    return 1
}

log_info "🚀 Starting graduated GitOps deployment..."

# Phase 1: Core Infrastructure (CRDs, operators, namespaces)
validate_kustomization "infrastructure-core" 600

# Phase 2: Platform Infrastructure (Istio, networking)  
validate_kustomization "infrastructure-platform" 600

# Phase 4: Security Policies (AuthorizationPolicies, RBAC)
validate_kustomization "infrastructure-security-policies" 600

# Phase 5: Infrastructure Services (backup, etc.)
validate_kustomization "infrastructure-backup" 300

# Phase 6: Monitoring Stack
validate_kustomization "apps-monitoring" 900

log_info "📊 Final validation - Checking all Kustomizations..."
flux get kustomizations

log_info "📊 Checking HelmReleases..."
flux get helmreleases

log_info "📊 Checking Sources..."
flux get sources all

log_info "🔍 Running comprehensive Flux health check..."
flux check

log_success "🎉 Migration to Flux v2 completed successfully!"
echo ""
log_info "📋 Next steps:"
echo "1. Monitor the deployment: watch kubectl get pods --all-namespaces"
echo "2. Check Flux logs: flux logs --all-namespaces"
echo "3. Access applications: https://grafana.dunde.live, https://n8n.dunde.live"
echo "4. Verify image automation is working: flux get images all"
echo "5. Check secret decryption: kubectl get secrets -A | grep sops"
echo ""
log_info "🔄 Useful commands:"
echo "- flux reconcile source git flux-system"
echo "- flux reconcile kustomization flux-system"
echo "- flux suspend kustomization <name>"
echo "- flux resume kustomization <name>"
echo "- flux logs --follow"
echo ""
log_warning "🔄 To rollback to ArgoCD if needed, run:"
echo "kubectl apply -f appofapps.yaml"