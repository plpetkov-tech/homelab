# Renovate Bot Quick Start Guide

Get Renovate running in 5 minutes.

## TL;DR

```bash
# 1. Create GitHub App or PAT (see below)
# 2. Add secrets to repository
# 3. Push renovate.json and workflow
git add renovate.json .github/workflows/renovate.yml
git commit -m "feat: add Renovate bot for automated dependency updates"
git push

# 4. Manually trigger first run
# GitHub > Actions > Renovate > Run workflow

# 5. Check for Dependency Dashboard issue
# GitHub > Issues > "Dependency Dashboard"
```

## Setup Method 1: GitHub App (Recommended)

**Pros**: Better security, higher API limits, fine-grained permissions

### Steps

1. **Create GitHub App**:
   - Go to https://github.com/settings/apps/new
   - Fill in:
     - Name: `Renovate Bot for Homelab`
     - Homepage URL: `https://github.com/plpetkov-tech/homelab`
     - Webhook: **Uncheck "Active"**
   - Permissions (Repository):
     - Contents: **Read & Write**
     - Metadata: **Read-only**
     - Pull Requests: **Read & Write**
     - Issues: **Read & Write**
     - Workflows: **Read & Write**
   - Install only on: **Only on this account**
   - Click **Create GitHub App**

2. **Get App Credentials**:
   - Note the **App ID** (shown on the app page)
   - Scroll down to **Private keys**
   - Click **Generate a private key**
   - Download the `.pem` file

3. **Install the App**:
   - On the app page, click **Install App**
   - Select your repository: `homelab`
   - Click **Install**

4. **Add Secrets**:
   - Go to your repo: Settings > Secrets and variables > Actions
   - Click **New repository secret**
   - Add two secrets:
     ```
     Name: RENOVATE_APP_ID
     Value: <your app ID from step 2>

     Name: RENOVATE_APP_PRIVATE_KEY
     Value: <paste the entire contents of the .pem file>
     ```

5. **Done!** The workflow is already configured to use the GitHub App.

## Setup Method 2: Personal Access Token

**Pros**: Simpler setup, good for testing

### Steps

1. **Create PAT**:
   - Go to https://github.com/settings/tokens/new
   - Fill in:
     - Note: `Renovate Bot`
     - Expiration: **No expiration** (or your preference)
     - Scopes:
       - ✅ `repo` (all)
       - ✅ `workflow`
   - Click **Generate token**
   - Copy the token (starts with `ghp_`)

2. **Add Secret**:
   - Go to your repo: Settings > Secrets and variables > Actions
   - Click **New repository secret**
   - Add:
     ```
     Name: RENOVATE_TOKEN
     Value: <paste your token>
     ```

3. **Switch Workflow**:
   ```bash
   cd /home/plamen/homelab

   # Remove GitHub App workflow
   rm .github/workflows/renovate.yml

   # Use PAT workflow instead
   mv .github/workflows/renovate-selfhosted.yml.example .github/workflows/renovate.yml

   # Commit
   git add .github/workflows/
   git commit -m "feat: use PAT for Renovate authentication"
   git push
   ```

## First Run

1. **Manual Trigger**:
   - GitHub > Actions > Renovate
   - Click **Run workflow**
   - Keep defaults (or enable dry-run for testing)
   - Click **Run workflow**

2. **Check Results**:
   - Wait 2-5 minutes
   - Check for new issue: **Dependency Dashboard**
   - Check for new pull requests with label `dependencies`

## What to Expect

### Dependency Dashboard Issue

Renovate creates a single issue that lists:
- ✅ All available updates
- ⏸️ Rate-limited or pending updates
- ❌ Errors or problems
- 🔧 Configuration issues

This is your control center for Renovate.

### Pull Requests

Renovate creates grouped PRs:

- **Helm Charts** (Sunday after 10pm)
  - All chart updates in one PR
  - Changelog links for each update

- **Istio** (Sunday after 10pm)
  - All Istio components together

- **Monitoring Stack** (Sunday after 10pm)
  - Prometheus, Grafana, Loki, Alloy

- **Terraform Providers** (Saturday after 10pm)
  - All provider updates together

- **Flux Components** (Saturday after 10pm)
  - All Flux system updates together

### Auto-merge

Only **patch updates** for stable charts auto-merge:
- cert-manager
- reflector
- k8tz

Everything else requires manual review.

## Common Tasks

### Trigger Specific Update

In the Dependency Dashboard issue:
- Find the update you want
- Check the box next to it
- Renovate will create a PR immediately

### Ignore an Update

In the Dependency Dashboard issue:
- Find the update
- Click "Ignore"
- Choose version or dependency to ignore

### Change Schedule

Edit `renovate.json`:

```json
{
  "schedule": ["every weekend"]
}
```

Commit and push. Renovate picks up changes on next run.

### Dry Run Test

Actions > Renovate > Run workflow
- Dry-Run: **true**
- Log-Level: **debug**

Renovate logs what it would do without creating PRs.

## Troubleshooting

### No PRs Created

1. Check workflow runs: Actions > Renovate
2. Look for errors in logs
3. Verify secrets are set correctly
4. Check Dependency Dashboard for extraction errors

### PRs Created but Not Auto-merging

1. Check branch protection rules
2. Ensure status checks are passing
3. Verify `automerge` is enabled for the package

### Updates Not Detected

1. Check Dependency Dashboard
2. Look for "extraction errors"
3. Verify file patterns in `renovate.json`
4. Run with debug logging

## Next Steps

- Read full docs: [docs/RENOVATE.md](./RENOVATE.md)
- Customize package rules in `renovate.json`
- Configure Slack/Discord notifications
- Set up auto-merge for more packages

## Schedule Reference

Default schedule (all times UTC):

| Update Type | Schedule |
|-------------|----------|
| Helm Charts | Sunday after 10pm |
| Istio | Sunday after 10pm |
| Monitoring | Sunday after 10pm |
| Terraform | Saturday after 10pm |
| Flux | Saturday after 10pm |
| General | Weeknights 10pm-5am, weekends |

## Support

- Full documentation: [docs/RENOVATE.md](./RENOVATE.md)
- Renovate docs: https://docs.renovatebot.com/
- Renovate Discord: https://discord.gg/renovate
