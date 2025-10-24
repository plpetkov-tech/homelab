#!/bin/bash

# Infrastructure Validation Script
# Validates cluster readiness before GitOps deployment

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

validate_dns() {
    log_info "🔍 Validating DNS resolution..."
    
    # Test external DNS resolution from host
    if ! timeout 5 nslookup google.com >/dev/null 2>&1; then
        log_error "❌ Host DNS resolution failed"
        return 1
    fi
    
    # Check if CoreDNS is running
    if ! kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | grep -q "Running"; then
        log_error "❌ CoreDNS is not running"
        return 1
    fi
    
    # Test pod DNS resolution
    if kubectl run dns-test --image=busybox --restart=Never --rm -i --timeout=30s -- nslookup google.com >/dev/null 2>&1; then
        log_success "✅ Pod DNS resolution working"
    else
        log_error "❌ Pod DNS resolution failed"
        return 1
    fi
    
    log_success "✅ DNS validation passed"
}

validate_cni() {
    log_info "🔍 Validating CNI (Cilium)..."
    
    # Check Cilium pods are running
    if ! kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | grep -q "Running"; then
        log_error "❌ Cilium is not running"
        return 1
    fi
    
    # Check Cilium connectivity
    local cilium_pod=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | head -1 | awk '{print $1}')
    if kubectl exec -n kube-system "$cilium_pod" -- cilium status --brief | grep -q "OK"; then
        log_success "✅ Cilium is healthy"
    else
        log_error "❌ Cilium health check failed"
        return 1
    fi
    
    log_success "✅ CNI validation passed"
}

validate_api_connectivity() {
    log_info "🔍 Validating Kubernetes API connectivity..."
    
    if kubectl cluster-info >/dev/null 2>&1; then
        log_success "✅ Kubernetes API is accessible"
    else
        log_error "❌ Kubernetes API is not accessible"
        return 1
    fi
    
    # Check API server health
    if kubectl get --raw='/healthz' >/dev/null 2>&1; then
        log_success "✅ Kubernetes API health check passed"
    else
        log_error "❌ Kubernetes API health check failed"
        return 1
    fi
    
    log_success "✅ API connectivity validation passed"
}

validate_storage() {
    log_info "🔍 Validating storage classes..."
    
    if kubectl get storageclass >/dev/null 2>&1; then
        local default_sc=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')
        if [ "$default_sc" != "" ]; then
            log_success "✅ Default storage class '$default_sc' found"
        else
            log_warning "⚠️ No default storage class found"
        fi
    else
        log_error "❌ Storage class validation failed"
        return 1
    fi
    
    log_success "✅ Storage validation passed"
}

validate_nodes() {
    log_info "🔍 Validating node readiness..."
    
    local ready_nodes=$(kubectl get nodes --no-headers | grep " Ready " | wc -l)
    local total_nodes=$(kubectl get nodes --no-headers | wc -l)
    
    if [ "$ready_nodes" -eq "$total_nodes" ] && [ "$ready_nodes" -gt 0 ]; then
        log_success "✅ All $ready_nodes nodes are ready"
    else
        log_error "❌ Only $ready_nodes/$total_nodes nodes are ready"
        kubectl get nodes
        return 1
    fi
    
    log_success "✅ Node validation passed"
}

main() {
    log_info "🚀 Starting infrastructure validation..."
    
    validate_api_connectivity || exit 1
    validate_nodes || exit 1
    validate_cni || exit 1
    validate_dns || exit 1
    validate_storage || exit 1
    
    log_success "🎉 Infrastructure validation completed successfully!"
    log_info "✅ Cluster is ready for GitOps deployment"
}

main "$@"