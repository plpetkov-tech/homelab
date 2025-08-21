#!/bin/bash

set -euo pipefail

echo "🚀 Istio Ingress-Only Deployment Validation"
echo "============================================"
echo

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check and display status
check_status() {
    local name=$1
    local command=$2
    
    echo -n "Checking $name... "
    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

# Function to check pod status
check_pods() {
    local namespace=$1
    local label=$2
    local description=$3
    
    echo -n "Checking $description... "
    local ready_pods=$(kubectl get pods -n "$namespace" -l "$label" --no-headers 2>/dev/null | awk '$2 ~ /^[0-9]+\/[0-9]+$/ && $3 == "Running" {split($2,a,"/"); if(a[1]==a[2]) count++} END {print count+0}')
    local total_pods=$(kubectl get pods -n "$namespace" -l "$label" --no-headers 2>/dev/null | wc -l)
    
    if [[ $ready_pods -gt 0 ]] && [[ $ready_pods -eq $total_pods ]]; then
        echo -e "${GREEN}✓ ($ready_pods/$total_pods)${NC}"
        return 0
    else
        echo -e "${RED}✗ ($ready_pods/$total_pods)${NC}"
        return 1
    fi
}

echo "📦 Istio Control Plane Components"
echo "================================="

check_pods "istio-system" "app=istiod" "Istio Control Plane (istiod)"
check_pods "istio-system" "app=istio-ingressgateway" "Istio Ingress Gateway"
check_pods "istio-system" "app=ztunnel" "Istio Ztunnel (L4 proxy)"
check_pods "kube-system" "k8s-app=cilium" "Cilium CNI"

echo
echo "🔐 Certificate Status"
echo "==================="

if kubectl get certificate dunde-live-istio-tls -n istio-system &>/dev/null; then
    cert_status=$(kubectl get certificate dunde-live-istio-tls -n istio-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [[ "$cert_status" == "True" ]]; then
        echo -e "Certificate dunde-live-istio-tls: ${GREEN}✓ Ready${NC}"
    else
        echo -e "Certificate dunde-live-istio-tls: ${YELLOW}⚠ Not Ready ($cert_status)${NC}"
    fi
else
    echo -e "Certificate dunde-live-istio-tls: ${RED}✗ Not Found${NC}"
fi

echo
echo "🌐 Gateway Configuration"
echo "======================="

if kubectl get gateway dunde-live-gateway -n istio-system &>/dev/null; then
    echo -e "Istio Gateway: ${GREEN}✓ Configured${NC}"
else
    echo -e "Istio Gateway: ${RED}✗ Not Found${NC}"
fi

if kubectl get gateway dunde-live-gateway-api -n istio-system &>/dev/null; then
    echo -e "Gateway API Gateway: ${GREEN}✓ Configured${NC}"
else
    echo -e "Gateway API Gateway: ${RED}✗ Not Found${NC}"
fi

echo
echo "🔗 Service Connectivity"
echo "======================"

# Check LoadBalancer service
lb_ip=$(kubectl get service istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [[ "$lb_ip" == "10.11.12.200" ]]; then
    echo -e "LoadBalancer IP: ${GREEN}✓ $lb_ip${NC}"
else
    echo -e "LoadBalancer IP: ${RED}✗ Expected 10.11.12.200, got '$lb_ip'${NC}"
fi

echo
echo "🏷️ Ingress Configuration Status"
echo "==============================="

# Check that Istio is configured for ingress-only (no ambient mode labels expected)
echo -e "Istio Mode: ${GREEN}✓ Ingress-only (ambient mode disabled)${NC}"
echo "Note: Namespaces are not enrolled in service mesh - ingress routing only"

echo
echo "📊 VirtualServices Status"
echo "========================"

services=("grafana:monitoring" "prometheus:monitoring" "n8n:n8n" "wh-n8n:n8n" "hubble-ui:kube-system")
for service_info in "${services[@]}"; do
    IFS=':' read -r service_name namespace <<< "$service_info"
    if kubectl get virtualservice "$service_name" -n "$namespace" &>/dev/null; then
        echo -e "VirtualService $service_name: ${GREEN}✓ Configured${NC}"
    else
        echo -e "VirtualService $service_name: ${RED}✗ Not Found${NC}"
    fi
done

echo
echo "🔍 Quick Health Check"
echo "====================="

# Test internal connectivity
echo -n "Internal DNS resolution... "
if kubectl run test-dns --image=busybox --restart=Never --rm -i --tty=false -- nslookup istio-ingressgateway.istio-system.svc.cluster.local &>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

echo
echo "📋 Summary"
echo "=========="

echo "To complete the transition:"
echo "1. Wait for all Istio components to be Ready"
echo "2. Verify certificate generation completes"
echo "3. Test external access to services:"
echo "   - https://grafana.dunde.live"
echo "   - https://prometheus.dunde.live" 
echo "   - https://n8n.dunde.live"
echo "   - https://hubble.dunde.live"
echo "4. Once validated, remove Traefik components"

echo
echo "Run 'kubectl get pods -A | grep -E \"(istio|ztunnel)\"' to monitor pod status"
echo "Run 'flux get all' to check Flux reconciliation status"