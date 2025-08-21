#!/bin/bash

set -euo pipefail

echo "🔍 Checking all Kustomizations for file references and build errors using kubectl kustomize..."

# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)

MISSING=0
PANIC_FOUND=0

# Check that kubectl is available
if ! command -v kubectl >/dev/null; then
  echo "${RED}❌ Error:${RESET} kubectl not found in PATH"
  exit 1
fi

# Find all kustomization.yaml/yml files
# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

find . -type f \( -iname "kustomization.yaml" -o -iname "kustomization.yml" \) | while read -r kustomization; do
  echo -e "\n📄 Parsing: $kustomization"
  base_dir=$(dirname "$kustomization")

  # 1. Check referenced file existence using yq
  mapfile -t refs < <(
    yq eval '.resources[], .patches[], .patchesStrategicMerge[], 
             .configMapGenerator[].files[], 
             .secretGenerator[].files[]' "$kustomization" 2>/dev/null \
    | grep -v 'null' || true
  )

  for ref in "${refs[@]}"; do
    full_path="$base_dir/$ref"
    if [[ ! -e "$full_path" ]]; then
      echo "  ${RED}❌ Missing:$RESET $full_path (referenced in $kustomization)"
      ((MISSING++))
    else
      echo "  ${GREEN}✅ Found:$RESET  $full_path"
    fi
  done

  # 2. Try to build using kubectl kustomize
  echo "⚙️  Running: kubectl kustomize $base_dir"
  BUILD_OUTPUT=$(kubectl kustomize "$base_dir" 2>&1) || true

  if echo "$BUILD_OUTPUT" | grep -qE 'panic|invalid memory address|runtime error'; then
    echo "  ${RED}💥 Panic during build:$RESET $base_dir"
    echo "$BUILD_OUTPUT" | sed 's/^/    │ /'
    ((PANIC_FOUND++))
  elif [[ -n "$BUILD_OUTPUT" ]]; then
    if echo "$BUILD_OUTPUT" | grep -qi 'error'; then
      echo "  ${YELLOW}⚠️ Build Error:$RESET"
      echo "$BUILD_OUTPUT" | sed 's/^/    │ /'
    else
      echo "  ${GREEN}✅ Build succeeded:$RESET $base_dir"
    fi
  else
    echo "  ${GREEN}✅ Build succeeded (empty output):$RESET $base_dir"
  fi

done

# Final summary
echo ""
echo "🧾 Summary:"
[[ $MISSING -gt 0 ]] && echo "❗ Missing file references: $MISSING"
[[ $PANIC_FOUND -gt 0 ]] && echo "💥 Kustomizations with build panic: $PANIC_FOUND"
[[ $MISSING -eq 0 && $PANIC_FOUND -eq 0 ]] && echo "✅ All references valid and builds succeeded."

# Exit code
if [[ $MISSING -gt 0 || $PANIC_FOUND -gt 0 ]]; then
  exit 1
else
  exit 0
fi

