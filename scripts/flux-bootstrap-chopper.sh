#!/bin/bash

# Flux v2 Bootstrap Script for Chopper (ARM K3s Cluster)

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

log_info "🚀 Starting Flux v2 Bootstrap for Chopper (ARM K3s Cluster)..."

# Set kubeconfig
export KUBECONFIG="$HOME/.kube/chopper"

# Check if flux CLI is installed
if ! command -v flux &> /dev/null; then
    log_error "Flux CLI not found. Please install it first:"
    echo "curl -s https://fluxcd.io/install.sh | sudo bash"
    exit 1
fi

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    log_error "kubectl is not configured or cluster is not accessible"
    log_error "Make sure kubeconfig is at $KUBECONFIG"
    exit 1
fi

# Show current context and cluster info
log_info "Current cluster nodes:"
kubectl get nodes

log_warning "This will bootstrap Flux on the chopper cluster"
read -p "Are you sure you want to continue? (y/N): " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Aborted by user."
    exit 0
fi

# Check if SOPS and age are installed
if ! command -v sops &> /dev/null; then
    log_error "SOPS not found. Please install it first"
    exit 1
fi

if ! command -v age &> /dev/null; then
    log_error "age not found. Please install it first"
    exit 1
fi

log_success "Prerequisites check passed"

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Set variables
GITHUB_USER="plpetkov-tech"
GITHUB_REPO="homelab"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
CLUSTER_PATH="flux/clusters/chopper"

if [ "$GITHUB_TOKEN" = "" ]; then
    log_error "GITHUB_TOKEN environment variable is required"
    echo "Please set it with: export GITHUB_TOKEN=<your-token>"
    exit 1
fi

# Check if age key exists
if [ ! -f "$REPO_ROOT/age.agekey" ]; then
    log_error "age.agekey not found at $REPO_ROOT/age.agekey"
    exit 1
fi

# Verify SOPS can decrypt (test with a known encrypted file)
log_info "Verifying SOPS can decrypt secrets..."
export SOPS_AGE_KEY_FILE="$REPO_ROOT/age.agekey"
if ! sops -d "$REPO_ROOT/flux/apps/base/demo/nginx-secret.yaml" > /dev/null 2>&1; then
    log_error "SOPS decryption test failed. Please check your age.agekey file."
    exit 1
fi
log_success "SOPS decryption test passed"

log_info "🔧 Bootstrapping Flux v2 with GitHub repository..."

# Bootstrap Flux
if flux bootstrap github \
  --owner="$GITHUB_USER" \
  --repository="$GITHUB_REPO" \
  --branch=main \
  --path="$CLUSTER_PATH" \
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

log_info "🔍 Waiting for Flux controllers to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/part-of=flux -n flux-system --timeout=300s

log_info "🔍 Checking Flux system status..."
kubectl get pods -n flux-system

log_info "🚀 Waiting for demo app kustomization to be ready..."
for i in {1..30}; do
    if kubectl get kustomization apps-demo -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        log_success "✅ Demo app kustomization is ready"
        break
    fi

    if kubectl get kustomization apps-demo -n flux-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null | grep -q "BuildFailed\|HealthCheckFailed"; then
        log_error "❌ Demo app kustomization failed"
        kubectl get kustomization apps-demo -n flux-system -o yaml
        exit 1
    fi

    log_info "⏳ Still waiting for demo app... (${i}0s/300s)"
    sleep 10
done

log_info "📊 Checking all Kustomizations..."
flux get kustomizations

log_info "📊 Checking Sources..."
flux get sources all

log_info "🔍 Running Flux health check..."
flux check

log_success "🎉 Flux v2 setup on Chopper cluster completed successfully!"
echo ""
log_info "📋 Verification steps:"
echo "1. Check the demo namespace: kubectl get all -n demo"
echo "2. Check the nginx pod logs: kubectl logs -n demo deployment/nginx"
echo "3. Verify secret was decrypted: kubectl get secret -n demo nginx-secret -o yaml"
echo "4. Port-forward to nginx: kubectl port-forward -n demo svc/nginx 8080:80"
echo ""
log_info "🔄 Useful commands:"
echo "- flux reconcile source git flux-system"
echo "- flux reconcile kustomization apps-demo"
echo "- flux logs --follow"
echo "- kubectl --kubeconfig ~/.kube/chopper get pods -A"
