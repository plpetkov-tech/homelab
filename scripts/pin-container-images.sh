#!/bin/bash

# Container Image SHA Digest Pinning Script
# Finds container image tags and replaces them with SHA digests

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

# Check if docker is available
if ! command -v docker &> /dev/null; then
    log_error "Docker not found. Please install Docker first."
    exit 1
fi

log_info "Using Docker to fetch image SHA digests"

# Function to get SHA digest from an image
get_sha_digest() {
    local image="$1"
    local digest=""
    
    echo -n "  Pulling $image... " >&2
    
    # Pull the image first
    if docker pull "$image" >/dev/null 2>&1; then
        echo "done" >&2
        
        # Get digest from RepoDigests (most reliable method)
        digest=$(docker inspect "$image" --format='{{index .RepoDigests 0}}' 2>/dev/null || echo "")
        
        if [[ -n "$digest" && "$digest" != "<no value>" ]]; then
            echo "$digest"
            return 0
        fi
        
        echo "  Warning: No RepoDigest found, trying alternative method..." >&2
        
        # Alternative: get image ID and construct digest
        local image_id=$(docker inspect "$image" --format='{{.Id}}' 2>/dev/null | cut -d: -f2)
        if [[ -n "$image_id" ]]; then
            local repo="${image%:*}"
            echo "$repo@sha256:$image_id"
            return 0
        fi
    else
        echo "failed" >&2
    fi
    
    echo "  Error: Failed to get digest for $image" >&2
    return 1
}

# Create backup directory
BACKUP_DIR="./image-pinning-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
log_info "Creating backup in $BACKUP_DIR"

# Create summary file
SUMMARY_FILE="./image-pinning-summary-$(date +%Y%m%d-%H%M%S).md"
echo "# Container Image SHA Digest Pinning Summary" > "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "**Date**: $(date)" >> "$SUMMARY_FILE"
echo "**Task**: Replace container image tags with SHA digests" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "| Original Image | SHA Digest | Status |" >> "$SUMMARY_FILE"
echo "|----------------|------------|--------|" >> "$SUMMARY_FILE"

# Find all image references and process them
log_info "Scanning for container images in YAML files..."

IMAGES_FOUND=0
IMAGES_PROCESSED=0
declare -A processed_images=() # Initialize empty associative array

# Search for image: lines in YAML files
while IFS= read -r file; do
    # Skip if file is in .git directory
    if [[ "$file" == *".git"* ]]; then
        continue
    fi
    
    # Copy original file to backup
    cp "$file" "$BACKUP_DIR/$(basename "$file").backup" 2>/dev/null || true
    
    # Process each line with image:
    while IFS= read -r line_content; do
        # Extract the image reference
        if [[ "$line_content" =~ image:[[:space:]]*[\"\']*([^[:space:]\"\']+)[\"\']*[[:space:]]*$ ]]; then
            full_image="${BASH_REMATCH[1]}"
            
            # Skip if already a digest
            if [[ "$full_image" == *"@sha256:"* ]]; then
                continue
            fi
            
            # Skip if not a tagged image
            if [[ "$full_image" != *":"* ]]; then
                continue
            fi
            
            # Skip specific images we don't want to update (like CUDA, flux system images with specific SHAs)
            if [[ "$full_image" == *"cuda"* ]] || [[ "$full_image" == *"ghcr.io/fluxcd/"* ]] || [[ "$full_image" == *"velero/velero-plugin-for-aws:"* && "$full_image" == *"80d5b5176d29d4f1294d7e561b3c13a3417d775f7479995171f5b147fc3c705e"* ]]; then
                continue
            fi
            
            # For images with specific version tags, try to get the latest version first
            if [[ "$full_image" == *":"* && "$full_image" != *":latest" ]]; then
                local base_image="${full_image%:*}"
                local current_tag="${full_image##*:}"
                
                # Try to use latest tag instead of the specific version for some images
                case "$base_image" in
                    "lscr.io/linuxserver/"*|"linuxserver/"*|"ghcr.io/meeb/tubesync"|"ghcr.io/hoarder-app/hoarder")
                        log_info "Getting latest version for $base_image"
                        full_image="$base_image:latest"
                        ;;
                esac
            fi
            
            IMAGES_FOUND=$((IMAGES_FOUND + 1))
            log_info "Processing: $full_image"
            
            # Check if we already processed this image
            if [[ -n "${processed_images[$full_image]:-}" ]]; then
                digest="${processed_images[$full_image]}"
                log_info "Using cached digest: $digest"
            else
                # Get the digest
                if digest=$(get_sha_digest "$full_image"); then
                    processed_images["$full_image"]="$digest"
                    log_success "Got digest: $digest"
                else
                    log_error "Failed to get digest for $full_image"
                    echo "| \`$full_image\` | N/A | ❌ Failed |" >> "$SUMMARY_FILE"
                    continue
                fi
            fi
            
            # Replace the image in the file using perl for better escaping
            if perl -pi -e "s|\\Q$full_image\\E|$digest|g" "$file" 2>/dev/null; then
                log_success "Updated in $file"
                echo "| \`$full_image\` | \`$digest\` | ✅ Success |" >> "$SUMMARY_FILE"
                IMAGES_PROCESSED=$((IMAGES_PROCESSED + 1))
            else
                log_error "Failed to update $file"
                echo "| \`$full_image\` | \`$digest\` | ❌ Failed |" >> "$SUMMARY_FILE"
            fi
            
        fi
    done < <(grep "image:" "$file" 2>/dev/null || true)
    
done < <(find . -name "*.yaml" -o -name "*.yml" | grep -v ".git")

# Add footer to summary
echo "" >> "$SUMMARY_FILE"
echo "## Summary" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "- **Images found**: $IMAGES_FOUND" >> "$SUMMARY_FILE"
echo "- **Images processed**: $IMAGES_PROCESSED" >> "$SUMMARY_FILE"
echo "- **Success rate**: $((IMAGES_FOUND > 0 ? IMAGES_PROCESSED * 100 / IMAGES_FOUND : 0))%" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "## Security Benefits" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "- **Immutable deployments**: Exact same image content every time" >> "$SUMMARY_FILE"
echo "- **Supply chain security**: SHA digests prevent image tampering" >> "$SUMMARY_FILE"
echo "- **Vulnerability tracking**: Can scan specific image builds" >> "$SUMMARY_FILE"
echo "- **Reproducible builds**: Byte-for-byte identical deployments" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "## Processed Images" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
if [[ ${#processed_images[@]} -gt 0 ]] 2>/dev/null; then
    for original in "${!processed_images[@]}"; do
        echo "- **$original** → \`${processed_images[$original]}\`" >> "$SUMMARY_FILE"
    done
else
    echo "No images were processed (all images may already use SHA digests)" >> "$SUMMARY_FILE"
fi
echo "" >> "$SUMMARY_FILE"
echo "## Backup Location" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "Original files backed up to: \`$BACKUP_DIR\`" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "## Next Steps" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "1. Review the changes: \`git diff\`" >> "$SUMMARY_FILE"
echo "2. Test the deployments in a staging environment" >> "$SUMMARY_FILE"
echo "3. Commit the changes: \`git add -A && git commit -m \"Pin container images to SHA digests\"\`" >> "$SUMMARY_FILE"

if [[ $IMAGES_FOUND -eq 0 ]]; then
    log_success "No container images found or all images already use SHA digests!"
else
    log_success "Image SHA digest pinning completed!"
    log_info "Images found: $IMAGES_FOUND"
    log_info "Images processed: $IMAGES_PROCESSED"
    log_info "Unique images processed: ${#processed_images[@]}"
    log_info "Summary written to: $SUMMARY_FILE"
    log_info "Backup created in: $BACKUP_DIR"
    
    if [[ ${#processed_images[@]} -gt 0 ]] 2>/dev/null; then
        echo ""
        log_info "=== PROCESSED IMAGES ==="
        for original in "${!processed_images[@]}"; do
            echo "  $original -> ${processed_images[$original]}"
        done
    fi
    
    echo ""
    log_warning "Please review the changes with 'git diff' before committing!"
    log_info "To commit: git add -A && git commit -m 'Pin container images to SHA digests for maximum security'"
fi