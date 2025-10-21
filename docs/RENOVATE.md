# Renovate Bot Setup Guide

This repository uses [Renovate Bot](https://docs.renovatebot.com/) to automatically keep dependencies up-to-date across multiple technology stacks.

## Overview

Renovate is configured to monitor and update:

- **Helm Charts** (17 HelmRelease resources)
- **Terraform Providers** (Proxmox, Unifi)
- **Container Images** (Flux components, plugins)
- **GitHub Actions** (workflow dependencies)

## What Renovate Manages

### Helm Charts (17 total)

Renovate monitors the following HelmRelease files:

#### Infrastructure Controllers
- k8tz (`flux/infrastructure/base/controllers/k8tz.yaml`)
- cert-manager (`flux/infrastructure/base/controllers/cert-manager.yaml`)
- cloudnative-pg (`flux/infrastructure/base/controllers/cnpg.yaml`)
- reflector (`flux/infrastructure/base/controllers/reflector.yaml`)
- Istio (base, istiod, gateway, cni) (`flux/infrastructure/base/controllers/istio.yaml`)
- kiali-operator (`flux/infrastructure/base/controllers/kiali.yaml`)

#### Backup & Security
- Velero (`flux/infrastructure/base/backup/velero-operator.yaml`)
- Trivy Operator (`flux/infrastructure/base/security-policies/trivy-operator.yaml`)

#### Monitoring Stack
- kube-prometheus-stack (`flux/apps/base/monitoring/kube-prometheus-stack.yaml`)
- Loki (`flux/apps/base/monitoring/loki.yaml`)
- Alloy (`flux/apps/base/monitoring/alloy.yaml`)

### Terraform Providers

Located in `terraform/providers.tf`:
- **bpg/proxmox** (currently v0.64.0)
- **paultyng/unifi** (currently v0.41.0)

### Container Images

- **Flux System Components** (`flux/clusters/homelab/flux-system/gotk-components.yaml`)
  - source-controller
  - kustomize-controller
  - helm-controller
  - notification-controller
  - image-reflector-controller
  - image-automation-controller

- **Velero Plugin Images** (`terraform/nodes.tf`)
  - velero/velero-plugin-for-aws

### What Renovate Does NOT Manage

- **Flux Image Policies**: The repository already uses Flux's built-in image automation for application images (Jellyfin, Radarr, Sonarr, n8n, Ollama, etc.). These are managed by `flux/clusters/homelab/image-automation.yaml`.
- **Ansible Playbooks**: No version constraints to update (playbooks are versioned via Git).

## Configuration

The main configuration file is `renovate.json` at the repository root.

### Key Features

#### Automatic Grouping
- **Helm Charts**: All chart updates grouped into a single PR
- **Istio**: All Istio components updated together
- **Monitoring Stack**: Prometheus, Grafana, Loki, Alloy grouped together
- **Terraform Providers**: All provider updates in one PR
- **Flux Components**: All Flux system components grouped together

#### Update Scheduling
- **Helm Charts**: Sundays after 10pm
- **Terraform Providers**: Saturdays after 10pm
- **Flux Components**: Saturdays after 10pm
- **General Updates**: Weeknights after 10pm, before 5am, or weekends

#### Security Features
- **Container Digest Pinning**: All container images are pinned by SHA256 digest
- **Vulnerability Alerts**: Enabled with OSV database integration
- **Security PRs**: High priority with special labels

#### Auto-merge Rules
- **Patch Updates**: Auto-merged for stable charts (cert-manager, reflector, k8tz)
- **Major Updates**: Always require manual review with special labels
- **Terraform & Flux**: Never auto-merged (require manual review)

#### PR Management
- **Concurrent Limit**: Maximum 5 PRs at once
- **Rebase Strategy**: Only when conflicted
- **Semantic Commits**: Enabled
- **Dependency Dashboard**: Enabled (creates a GitHub issue with all updates)

## Setup Instructions

### Prerequisites

You need either:

**Option 1: GitHub App (Recommended)**
- Better security with fine-grained permissions
- Higher API rate limits
- Easier to manage across multiple repositories

**Option 2: Personal Access Token (PAT)**
- Simpler setup
- Works for single repository

### Option 1: Setup with GitHub App

1. **Create a GitHub App**:
   - Go to GitHub Settings > Developer settings > GitHub Apps > New GitHub App
   - Name: `Renovate Bot for Homelab`
   - Homepage URL: `https://github.com/plpetkov-tech/homelab`
   - Webhook: Disable
   - Permissions:
     - Repository permissions:
       - Contents: Read & Write
       - Metadata: Read-only
       - Pull Requests: Read & Write
       - Issues: Read & Write
       - Workflows: Read & Write
   - Where can this GitHub App be installed?: Only on this account
   - Create the app

2. **Install the GitHub App**:
   - Go to the app settings page
   - Click "Install App"
   - Select your repository

3. **Add Secrets to Repository**:
   ```bash
   # Navigate to your repository on GitHub
   # Settings > Secrets and variables > Actions > New repository secret

   # Add two secrets:
   # 1. RENOVATE_APP_ID (the App ID from the app settings page)
   # 2. RENOVATE_APP_PRIVATE_KEY (generate and download from the app settings)
   ```

4. **Enable the Workflow**:
   - The workflow file is already created: `.github/workflows/renovate.yml`
   - Push your changes to the `main` branch
   - Go to Actions tab and verify the workflow appears

5. **Manual Trigger** (Optional):
   ```bash
   # Go to Actions > Renovate > Run workflow
   # Select branch: main
   # Click "Run workflow"
   ```

### Option 2: Setup with Personal Access Token

1. **Create a PAT**:
   - Go to GitHub Settings > Developer settings > Personal access tokens > Tokens (classic)
   - Generate new token (classic)
   - Name: `Renovate Bot`
   - Expiration: No expiration (or your preference)
   - Scopes:
     - `repo` (Full control of private repositories)
     - `workflow` (Update GitHub Action workflows)
   - Generate token and copy it

2. **Add Secret to Repository**:
   ```bash
   # Navigate to your repository on GitHub
   # Settings > Secrets and variables > Actions > New repository secret

   # Add secret:
   # Name: RENOVATE_TOKEN
   # Value: <paste your PAT>
   ```

3. **Switch to PAT Workflow**:
   ```bash
   cd /home/plamen/homelab

   # Remove the GitHub App workflow
   rm .github/workflows/renovate.yml

   # Rename the PAT example workflow
   mv .github/workflows/renovate-selfhosted.yml.example .github/workflows/renovate.yml

   # Commit and push
   git add .github/workflows/
   git commit -m "feat: configure Renovate with PAT authentication"
   git push
   ```

### Verify Installation

1. **Check Dependency Dashboard**:
   - After the first run, Renovate will create an issue titled "Dependency Dashboard"
   - This issue lists all available updates

2. **Check for PRs**:
   - Renovate will create Pull Requests for updates based on the schedule
   - PRs are labeled with `dependencies` and `renovate`

3. **Monitor Workflow Runs**:
   - Go to Actions tab
   - Check the "Renovate" workflow runs
   - Review logs for any errors

## Usage

### Manual Trigger

You can manually trigger Renovate anytime:

1. Go to **Actions** > **Renovate**
2. Click **Run workflow**
3. Optional: Enable dry-run mode or change log level
4. Click **Run workflow**

### Dry Run Mode

To test Renovate without creating actual PRs:

```bash
# Via GitHub Actions UI
Actions > Renovate > Run workflow
- Dry-Run: true
- Log-Level: debug
```

### Reviewing Updates

1. **Check the Dependency Dashboard Issue**:
   - Lists all pending updates
   - Shows what's being suppressed
   - Allows you to trigger updates manually

2. **Review Pull Requests**:
   - Each PR includes:
     - Changelog from the dependency
     - Version diff
     - Release notes (when available)
     - Compatibility information

3. **Approve and Merge**:
   - Test the changes in your cluster
   - Review breaking changes
   - Merge when ready

### Customizing Behavior

#### Ignoring Specific Updates

Add to `renovate.json`:

```json
{
  "packageRules": [
    {
      "matchPackagePatterns": ["istio"],
      "enabled": false
    }
  ]
}
```

#### Changing Update Schedule

Modify the schedule in `renovate.json`:

```json
{
  "packageRules": [
    {
      "matchDatasources": ["helm"],
      "schedule": ["every weekend"]
    }
  ]
}
```

#### Enabling Auto-merge for More Packages

Add to `renovate.json`:

```json
{
  "packageRules": [
    {
      "matchPackagePatterns": ["your-package"],
      "automerge": true
    }
  ]
}
```

## Troubleshooting

### Renovate Not Creating PRs

1. **Check Workflow Runs**:
   - Go to Actions > Renovate
   - Look for failed runs
   - Check logs for errors

2. **Verify Permissions**:
   - GitHub App or PAT has correct permissions
   - Repository settings allow Actions to create PRs

3. **Check Rate Limits**:
   - GitHub API rate limits may be hit
   - GitHub Apps have higher limits than PATs

### PRs Not Auto-merging

1. **Branch Protection Rules**:
   - Check repository settings > Branches
   - Ensure auto-merge is allowed

2. **PR Checks Failing**:
   - Auto-merge only works if all checks pass
   - Review any failing CI/CD checks

### Updates Not Detected

1. **Check Dependency Dashboard**:
   - Shows all detected dependencies
   - Lists any extraction errors

2. **Verify File Patterns**:
   - Ensure file paths match patterns in `renovate.json`
   - Check `fileMatch` patterns

3. **Enable Debug Logging**:
   ```bash
   Actions > Renovate > Run workflow
   - Log-Level: debug
   ```

### Test Configuration Locally

```bash
# Install Renovate CLI
npm install -g renovate

# Run validation
renovate-config-validator

# Run in dry-run mode
RENOVATE_TOKEN="your-token" renovate --dry-run plpetkov-tech/homelab
```

## Best Practices

1. **Review the Dependency Dashboard Weekly**:
   - Check for security updates
   - Review major version updates
   - Monitor Renovate status

2. **Test Updates in Stages**:
   - Test updates in a development cluster first
   - Gradually roll out to production

3. **Keep Renovate Updated**:
   - The workflow uses `latest` Renovate version
   - Monitor Renovate release notes

4. **Monitor Flux Reconciliation**:
   - After merging Helm chart updates, check Flux
   - Verify HelmReleases reconcile successfully
   - Watch for any errors in Flux

5. **Enable Renovate Notifications** (Optional):
   - Configure Slack/Discord webhooks
   - Get notified of new PRs

## Additional Resources

- [Renovate Documentation](https://docs.renovatebot.com/)
- [Flux Image Automation](https://fluxcd.io/flux/guides/image-update/)
- [Terraform Renovate Guide](https://docs.renovatebot.com/modules/manager/terraform/)
- [Kubernetes Renovate Guide](https://docs.renovatebot.com/modules/manager/kubernetes/)

## Support

For issues or questions:
- Check the [Renovate GitHub Issues](https://github.com/renovatebot/renovate/issues)
- Review the [Renovate Discussions](https://github.com/renovatebot/renovate/discussions)
- Consult the [Renovate Discord](https://discord.gg/renovate)
