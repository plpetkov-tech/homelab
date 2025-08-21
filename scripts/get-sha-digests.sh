#!/bin/bash

# Get SHA digests for container images
# This script pulls images and gets their actual SHA digests

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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get SHA digest from an image
get_sha_digest() {
    local image="$1"
    local digest=""
    
    log_info "Getting SHA digest for $image..."
    
    # Pull the image first
    if docker pull "$image" >/dev/null 2>&1; then
        # Method 1: Try to get digest from inspect
        digest=$(docker inspect "$image" --format='{{index .RepoDigests 0}}' 2>/dev/null || echo "")
        
        if [[ -n "$digest" && "$digest" != "<no value>" ]]; then
            echo "$digest"
            return 0
        fi
        
        # Method 2: Use manifest inspect
        digest=$(docker buildx imagetools inspect "$image" --raw 2>/dev/null | sha256sum | cut -d' ' -f1 || echo "")
        
        if [[ -n "$digest" ]]; then
            local repo="${image%:*}"
            echo "$repo@sha256:$digest"
            return 0
        fi
        
        # Method 3: Get image ID and convert
        local image_id=$(docker inspect "$image" --format='{{.Id}}' 2>/dev/null | cut -d: -f2)
        if [[ -n "$image_id" ]]; then
            local repo="${image%:*}"
            echo "$repo@sha256:$image_id"
            return 0
        fi
    fi
    
    log_error "Failed to get digest for $image"
    return 1
}

# Images to process
declare -A IMAGES=(
    ["linuxserver/deluge:2.1.1"]=""
    ["linuxserver/jellyfin:10.10.3"]=""
    ["linuxserver/jackett:0.23.0"]=""
    ["linuxserver/radarr:5.14.0"]=""
    ["linuxserver/sonarr:4.0.11"]=""
    ["ghcr.io/meeb/tubesync:v0.13.6"]=""
)

log_info "Getting SHA digests for all container images..."
echo ""

# Process each image
for image in "${!IMAGES[@]}"; do
    if digest=$(get_sha_digest "$image"); then
        IMAGES["$image"]="$digest"
        log_success "✅ $image -> $digest"
    else
        log_error "❌ Failed to get digest for $image"
    fi
    echo ""
done

echo ""
log_info "=== REPLACEMENT COMMANDS ==="
echo ""

# Generate replacement commands
for image in "${!IMAGES[@]}"; do
    digest="${IMAGES[$image]}"
    if [[ -n "$digest" ]]; then
        echo "# Replace $image with digest"
        echo "sed -i 's|$image|$digest|g' flux/apps/base/media/newgen_arrstack.yaml"
        echo ""
    fi
done

echo ""
log_info "=== SUMMARY ==="
for image in "${!IMAGES[@]}"; do
    digest="${IMAGES[$image]}"
    if [[ -n "$digest" ]]; then
        echo "✅ $image -> $digest"
    else
        echo "❌ $image -> FAILED"
    fi
done