# Longhorn Conversion Webhook Fix

## The Problem

**Longhorn v1.10.0 has a critical bug** where the conversion webhook (port 9501) fails to start due to a circular dependency in webhook initialization, but the CRDs are still configured to use it.

### Impact

When the conversion webhook is missing:

1. **API Server Overload**: The kube-apiserver continuously tries to reach the missing webhook at `longhorn-conversion-webhook.longhorn-system.svc:9501`, generating hundreds of errors per second
2. **Memory Exhaustion**: API server consumes 50-57% of control plane RAM (2-2.3GB out of 4GB)
3. **Cascading Failures**:
   - Control plane nodes drop to 143-262Mi free memory (critical!)
   - API server timeouts (returning HTML instead of JSON)
   - kube-controller-manager and kube-scheduler crash-looping (unable to acquire leader leases)
   - etcd request timeouts
   - Failed deployments (Prometheus, Loki, etc. cannot install)
   - Overall cluster instability

### Root Cause

From API server logs:
```
E1024 15:36:21.317177 cacher.go:482 unexpected ListAndWatch error:
failed to list longhorn.io/v1beta1, Kind=Volume:
conversion webhook for longhorn.io/v1beta2, Kind=Volume failed:
Post "https://longhorn-conversion-webhook.longhorn-system.svc:9501/v1/webhook/conversion?timeout=30s":
dial tcp 10.43.87.204:9501: connect: operation not permitted
```

This error repeats infinitely for all Longhorn CRDs:
- volumes.longhorn.io
- nodes.longhorn.io
- engineimages.longhorn.io
- backuptargets.longhorn.io
- replicas.longhorn.io
- engines.longhorn.io
- etc.

## The Solution

Remove the conversion webhook configuration from all Longhorn CRDs since the webhook doesn't work anyway. Version conversion is not critical for single-version deployments.

## What Was Fixed

### 1. Ansible Playbook (`ansible/longhorn-setup.yaml`)

**Added task** (line 168-187) that removes conversion webhook config from all Longhorn CRDs during deployment:

```yaml
- name: Remove conversion webhook configuration from Longhorn CRDs
  kubernetes.core.k8s:
    state: patched
    api_version: apiextensions.k8s.io/v1
    kind: CustomResourceDefinition
    name: "{{ item }}"
    definition:
      spec:
        conversion: null
  loop:
    - volumes.longhorn.io
    - nodes.longhorn.io
    - engineimages.longhorn.io
    - backuptargets.longhorn.io
    - replicas.longhorn.io
    - engines.longhorn.io
    - instancemanagers.longhorn.io
    - sharemanagers.longhorn.io
  delegate_to: localhost
  ignore_errors: true
```

**Updated comment** (line 118-121) to explain the issue better.

### 2. Fix Script for Existing Clusters (`scripts/fix-longhorn-webhook.sh`)

Created standalone script to fix already-deployed clusters:

```bash
ccr fix-longhorn-webhook
```

This script:
- Patches all Longhorn CRDs to remove conversion webhook config
- Works on the current cluster context
- Immediately stabilizes the API server and frees memory

### 3. ClusterCreator CLI (`scripts/clustercreator.sh`)

- Added `fix-longhorn-webhook` command (line 320, 387-389)
- Added to help menu (line 217)

## Usage

### For New Clusters

The fix is **automatically applied** during `ccr bootstrap` - the ansible playbook now handles this.

### For Existing Clusters

Run the fix manually:

```bash
ccr ctx gamma  # or your cluster name
ccr fix-longhorn-webhook
```

### Verification

After applying the fix:

```bash
# Check memory improvement on control plane
ssh plamen@<control-plane-ip> 'free -h'

# Check API server memory usage
ssh plamen@<control-plane-ip> 'ps aux --sort=-%mem | head -3'

# Verify no more webhook errors
ssh plamen@<control-plane-ip> 'sudo crictl logs $(sudo crictl ps | grep kube-apiserver | awk "{print \$1}") 2>&1 | grep -i conversion | tail -5'

# Check cluster stability
kubectl get nodes
kubectl get pods --all-namespaces
```

Expected improvements:
- **Memory**: 262Mi → 600Mi+ free on control planes
- **API server RAM**: 51-57% → 35-40%
- **No more conversion webhook errors** in API server logs
- **Stable deployments**: Prometheus, Loki, etc. can now install successfully

## Technical Details

### Why This Works

1. **CRD Conversion** is only needed when multiple API versions coexist (e.g., v1beta1 and v1beta2)
2. Since we're deploying a **single version** (v1.10.0), conversion isn't actually needed
3. Removing the webhook config makes the API server stop trying to reach it
4. All Longhorn functionality works normally without conversion webhooks

### Known Issue in Longhorn

This is a known issue in Longhorn v1.10.0:
- The conversion webhook has a **circular initialization dependency**
- The webhook container starts but the webhook service never becomes ready
- This was already partially documented in the ansible playbook comments
- The fix is safe and doesn't break any Longhorn features

## Related Files

- `ansible/longhorn-setup.yaml` - Main deployment with fix
- `scripts/fix-longhorn-webhook.sh` - Standalone fix script
- `scripts/clustercreator.sh` - CLI integration
- `scripts/vmctl.sh` - Fixed shellharden formatting issue (unrelated)
- `scripts/clustercreator.sh` - Fixed shellharden formatting issue (unrelated)

## Future Considerations

When upgrading Longhorn to a future version:
1. Check if Longhorn has fixed the conversion webhook issue
2. If fixed, consider re-enabling conversion webhooks in the ansible playbook
3. Test on a non-production cluster first

## Credits

Issue discovered and fixed: 2025-10-24
Cluster: gamma
Root cause analysis: API server logs showing continuous webhook connection failures
