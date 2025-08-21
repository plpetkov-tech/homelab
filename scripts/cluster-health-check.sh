#!/bin/bash

usage() {
  echo "Usage: ccr health-check [OPTIONS]"
  echo ""
  echo "Performs comprehensive health checks on the Kubernetes cluster"
  echo ""
  echo "Options:"
  echo "  --gpu-only       Check only GPU-related components"
  echo "  --control-plane  Check only control plane components"
  echo "  --storage        Check only storage components"
  echo "  --fix            Attempt automatic fixes for common issues"
  echo "  -h, --help       Show this help message"
  echo ""
  echo "This script validates:"
  echo " * Control plane component health (kubevip, etcd, scheduler, controller-manager)"
  echo " * Node status and resource availability"
  echo " * GPU operator and device plugin status"
  echo " * Storage (Longhorn) health"
  echo " * Network connectivity and CNI status"
  echo " * Critical addon status (metrics-server, flux, etc.)"
}

# Parse command-line arguments
GPU_ONLY=false
CONTROL_PLANE_ONLY=false
STORAGE_ONLY=false
AUTO_FIX=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --gpu-only) GPU_ONLY=true ;;
        --control-plane) CONTROL_PLANE_ONLY=true ;;
        --storage) STORAGE_ONLY=true ;;
        --fix) AUTO_FIX=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Health check counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_CHECKS++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNING_CHECKS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_CHECKS++))
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        log_error "Required command '$1' not found"
        return 1
    fi
}

# Check if we have kubectl access
check_kubectl_access() {
    log_info "Checking kubectl access..."
    ((TOTAL_CHECKS++))
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl cannot connect to cluster"
        return 1
    fi
    
    log_success "kubectl access verified"
    return 0
}

# Check control plane components
check_control_plane() {
    if [[ "$GPU_ONLY" == "true" || "$STORAGE_ONLY" == "true" ]]; then
        return 0
    fi
    
    log_info "Checking control plane components..."
    
    # Check kubevip
    ((TOTAL_CHECKS++))
    log_info "  Checking kube-vip status..."
    
    local kubevip_pods
    kubevip_pods=$(kubectl get pods -n kube-system -l component=kube-vip --no-headers 2>/dev/null | wc -l)
    
    if [[ "$kubevip_pods" -eq 0 ]]; then
        # Check static pods
        local static_kubevip
        static_kubevip=$(kubectl get pods -n kube-system -l k8s-app=kube-vip --no-headers 2>/dev/null | grep "Running" | wc -l)
        
        if [[ "$static_kubevip" -gt 0 ]]; then
            log_success "kube-vip running as static pod ($static_kubevip instances)"
        else
            log_error "kube-vip not running"
            if [[ "$AUTO_FIX" == "true" ]]; then
                log_info "    Attempting to restart kubelet to recover kube-vip..."
                # This would need to be run on control plane nodes
                log_warning "    Manual intervention required: restart kubelet on control plane nodes"
            fi
        fi
    else
        log_success "kube-vip running ($kubevip_pods pods)"
    fi
    
    # Check etcd
    ((TOTAL_CHECKS++))
    log_info "  Checking etcd status..."
    
    local etcd_health
    etcd_health=$(kubectl get componentstatuses 2>/dev/null | grep etcd | grep -c "Healthy" || echo "0")
    
    if [[ "$etcd_health" -gt 0 ]]; then
        log_success "etcd healthy"
    else
        # Try alternative check
        local etcd_endpoints
        etcd_endpoints=$(kubectl get pods -n kube-system -l component=etcd --no-headers 2>/dev/null | grep "Running" | wc -l)
        
        if [[ "$etcd_endpoints" -gt 0 ]]; then
            log_success "etcd pods running ($etcd_endpoints instances)"
        else
            log_error "etcd not healthy"
        fi
    fi
    
    # Check scheduler and controller-manager
    for component in "kube-scheduler" "kube-controller-manager"; do
        ((TOTAL_CHECKS++))
        log_info "  Checking $component..."
        
        local component_pods
        component_pods=$(kubectl get pods -n kube-system -l component=$component --no-headers 2>/dev/null | grep "Running" | wc -l)
        
        if [[ "$component_pods" -gt 0 ]]; then
            log_success "$component running ($component_pods instances)"
        else
            log_error "$component not running"
        fi
    done
}

# Check node status
check_nodes() {
    if [[ "$GPU_ONLY" == "true" || "$STORAGE_ONLY" == "true" ]]; then
        return 0
    fi
    
    log_info "Checking node status..."
    
    ((TOTAL_CHECKS++))
    local ready_nodes not_ready_nodes
    ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    not_ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -v "Ready" | wc -l || echo "0")
    
    if [[ "$not_ready_nodes" -eq 0 ]]; then
        log_success "All nodes ready ($ready_nodes nodes)"
    else
        log_warning "$not_ready_nodes nodes not ready, $ready_nodes nodes ready"
        
        # Show problematic nodes
        kubectl get nodes --no-headers 2>/dev/null | grep -v "Ready" | while read line; do
            log_warning "  Not ready: $line"
        done
    fi
}

# Check GPU components
check_gpu() {
    if [[ "$CONTROL_PLANE_ONLY" == "true" || "$STORAGE_ONLY" == "true" ]]; then
        return 0
    fi
    
    log_info "Checking GPU components..."
    
    # Check if GPU nodes exist
    local gpu_nodes
    gpu_nodes=$(kubectl get nodes -l nodeclass=gpu --no-headers 2>/dev/null | wc -l)
    
    if [[ "$gpu_nodes" -eq 0 ]]; then
        log_warning "No GPU nodes found in cluster"
        return 0
    fi
    
    log_info "  Found $gpu_nodes GPU nodes"
    
    # Check GPU operator namespace
    ((TOTAL_CHECKS++))
    if kubectl get namespace gpu-operator &> /dev/null; then
        log_success "GPU operator namespace exists"
        
        # Check GPU operator pods
        ((TOTAL_CHECKS++))
        local running_gpu_pods total_gpu_pods
        running_gpu_pods=$(kubectl get pods -n gpu-operator --no-headers 2>/dev/null | grep "Running" | wc -l)
        total_gpu_pods=$(kubectl get pods -n gpu-operator --no-headers 2>/dev/null | wc -l)
        
        if [[ "$running_gpu_pods" -eq "$total_gpu_pods" && "$total_gpu_pods" -gt 0 ]]; then
            log_success "All GPU operator pods running ($running_gpu_pods/$total_gpu_pods)"
        else
            log_warning "GPU operator pods status: $running_gpu_pods/$total_gpu_pods running"
            
            if [[ "$AUTO_FIX" == "true" ]]; then
                log_info "    Attempting to restart failed GPU operator pods..."
                kubectl delete pods -n gpu-operator --field-selector=status.phase=Failed &> /dev/null || true
            fi
        fi
        
        # Check GPU resources
        ((TOTAL_CHECKS++))
        local gpu_resource_nodes
        gpu_resource_nodes=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[] | select(.status.allocatable."nvidia.com/gpu" != null) | .metadata.name' | wc -l)
        
        if [[ "$gpu_resource_nodes" -gt 0 ]]; then
            log_success "GPU resources available on $gpu_resource_nodes nodes"
            
            # Show GPU allocation details
            kubectl get nodes -o custom-columns="NODE:.metadata.name,GPU_ALLOCATABLE:.status.allocatable.nvidia\.com/gpu,GPU_CAPACITY:.status.capacity.nvidia\.com/gpu" 2>/dev/null | grep -v "<none>" | while read line; do
                if [[ "$line" != *"NODE"* ]]; then
                    log_info "    $line"
                fi
            done
        else
            log_error "No GPU resources available"
            
            if [[ "$AUTO_FIX" == "true" ]]; then
                log_info "    Checking fallback device plugin..."
                
                # Check if fallback device plugin exists
                if ! kubectl get daemonset -n kube-system nvidia-device-plugin-fallback &> /dev/null; then
                    log_info "    Deploying fallback device plugin..."
                    # Here we would deploy the fallback device plugin
                    log_warning "    Manual intervention required: deploy fallback device plugin"
                fi
            fi
        fi
    else
        log_error "GPU operator namespace not found"
        
        if [[ "$AUTO_FIX" == "true" ]]; then
            log_info "    GPU operator needs to be installed"
            log_warning "    Manual intervention required: run 'ccr bootstrap --addons-only'"
        fi
    fi
    
    # Check for GPU test capabilities
    ((TOTAL_CHECKS++))
    log_info "  Testing GPU functionality..."
    
    if kubectl run gpu-test-health --rm --restart=Never --image=nvidia/cuda:12.0-runtime-ubuntu20.04 \
        --overrides='{"spec":{"tolerations":[{"key":"gpu","operator":"Equal","value":"true","effect":"NoSchedule"}],"nodeSelector":{"nvidia.com/gpu":"true"}}}' \
        --timeout=60s -- nvidia-smi &> /dev/null; then
        log_success "GPU test successful"
    else
        log_warning "GPU test failed or timed out"
    fi
}

# Check storage
check_storage() {
    if [[ "$GPU_ONLY" == "true" || "$CONTROL_PLANE_ONLY" == "true" ]]; then
        return 0
    fi
    
    log_info "Checking storage components..."
    
    # Check Longhorn
    ((TOTAL_CHECKS++))
    if kubectl get namespace longhorn-system &> /dev/null; then
        log_success "Longhorn namespace exists"
        
        # Check Longhorn manager pods
        ((TOTAL_CHECKS++))
        local longhorn_managers
        longhorn_managers=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | grep "Running" | wc -l)
        
        if [[ "$longhorn_managers" -gt 0 ]]; then
            log_success "Longhorn managers running ($longhorn_managers instances)"
        else
            log_error "Longhorn managers not running"
        fi
        
        # Check storage classes
        ((TOTAL_CHECKS++))
        if kubectl get storageclass longhorn &> /dev/null; then
            log_success "Longhorn storage class exists"
        else
            log_error "Longhorn storage class missing"
        fi
    else
        log_warning "Longhorn not installed"
    fi
}

# Check network components
check_network() {
    if [[ "$GPU_ONLY" == "true" ]]; then
        return 0
    fi
    
    log_info "Checking network components..."
    
    # Check CNI pods (Cilium)
    ((TOTAL_CHECKS++))
    local cilium_pods
    cilium_pods=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | grep "Running" | wc -l)
    
    if [[ "$cilium_pods" -gt 0 ]]; then
        log_success "Cilium pods running ($cilium_pods instances)"
    else
        log_error "Cilium pods not running"
    fi
    
    # Check MetalLB
    ((TOTAL_CHECKS++))
    if kubectl get namespace metallb-system &> /dev/null; then
        local metallb_controller metallb_speakers
        metallb_controller=$(kubectl get pods -n metallb-system -l app=metallb,component=controller --no-headers 2>/dev/null | grep "Running" | wc -l)
        metallb_speakers=$(kubectl get pods -n metallb-system -l app=metallb,component=speaker --no-headers 2>/dev/null | grep "Running" | wc -l)
        
        if [[ "$metallb_controller" -gt 0 && "$metallb_speakers" -gt 0 ]]; then
            log_success "MetalLB running (controller: $metallb_controller, speakers: $metallb_speakers)"
        else
            log_warning "MetalLB issues (controller: $metallb_controller, speakers: $metallb_speakers)"
        fi
    else
        log_warning "MetalLB not installed"
    fi
}

# Check critical addons
check_addons() {
    if [[ "$GPU_ONLY" == "true" ]]; then
        return 0
    fi
    
    log_info "Checking critical addons..."
    
    # Check metrics-server
    ((TOTAL_CHECKS++))
    local metrics_server
    metrics_server=$(kubectl get pods -n kube-system -l k8s-app=metrics-server --no-headers 2>/dev/null | grep "Running" | wc -l)
    
    if [[ "$metrics_server" -gt 0 ]]; then
        log_success "Metrics server running"
    else
        log_error "Metrics server not running"
    fi
    
    # Check Flux
    ((TOTAL_CHECKS++))
    if kubectl get namespace flux-system &> /dev/null; then
        local flux_pods
        flux_pods=$(kubectl get pods -n flux-system --no-headers 2>/dev/null | grep "Running" | wc -l)
        
        if [[ "$flux_pods" -gt 0 ]]; then
            log_success "Flux running ($flux_pods pods)"
        else
            log_warning "Flux pods not all running"
        fi
    else
        log_warning "Flux not installed"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🔍 ClusterCreator Health Check${NC}"
    echo "==============================="
    
    # Check prerequisites
    if ! check_command kubectl; then
        exit 1
    fi
    
    if ! check_kubectl_access; then
        exit 1
    fi
    
    # Run health checks
    check_control_plane
    check_nodes
    check_gpu
    check_storage
    check_network
    check_addons
    
    # Summary
    echo ""
    echo -e "${BLUE}📊 Health Check Summary${NC}"
    echo "========================"
    echo -e "Total checks: $TOTAL_CHECKS"
    echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}"
    echo -e "${YELLOW}Warnings: $WARNING_CHECKS${NC}"
    echo -e "${RED}Failed: $FAILED_CHECKS${NC}"
    
    if [[ "$FAILED_CHECKS" -eq 0 ]]; then
        echo -e "${GREEN}✅ Cluster is healthy!${NC}"
        exit 0
    elif [[ "$FAILED_CHECKS" -lt 3 ]]; then
        echo -e "${YELLOW}⚠️  Cluster has minor issues${NC}"
        exit 1
    else
        echo -e "${RED}❌ Cluster has major issues${NC}"
        exit 2
    fi
}

# Run main function
main "$@"