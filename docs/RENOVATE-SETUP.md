# Renovate Bot Setup - Step by Step Guide

This guide will walk you through setting up Renovate bot using GitHub App authentication.

## Prerequisites

- Repository pushed to GitHub: `plpetkov-tech/homelab`
- GitHub account with admin access to the repository
- 10 minutes of your time

---

## Step 1: Create the GitHub App

### 1.1 Navigate to GitHub Apps Settings

Open your browser and go to:
```
https://github.com/settings/apps/new
```

Or manually:
1. Go to GitHub.com
2. Click your profile picture (top right)
3. Click **Settings**
4. Scroll down to **Developer settings** (bottom left)
5. Click **GitHub Apps**
6. Click **New GitHub App**

### 1.2 Fill in Basic Information

**GitHub App name**:
```
Renovate Bot - Homelab
```
> Note: This name must be globally unique across GitHub. If taken, try: `Renovate-Homelab-<your-username>`

**Homepage URL**:
```
https://github.com/plpetkov-tech/homelab
```

**Webhook**:
- **Uncheck** the box that says "Active"
- We don't need webhooks for this setup

### 1.3 Set Permissions

Scroll down to **Permissions** section.

Under **Repository permissions**, set the following:

| Permission | Access Level |
|------------|--------------|
| **Contents** | Read and write |
| **Metadata** | Read-only (automatically set) |
| **Pull requests** | Read and write |
| **Issues** | Read and write |
| **Workflows** | Read and write |

Leave all other permissions as "No access".

### 1.4 Set Installation Options

Scroll down to **Where can this GitHub App be installed?**

Select:
- ⚪ **Only on this account**

### 1.5 Create the App

Click the green **Create GitHub App** button at the bottom.

---

## Step 2: Get App Credentials

After creating the app, you'll be redirected to the app's settings page.

### 2.1 Note the App ID

At the top of the page, you'll see:

```
App ID: 123456
```

**Copy this number** - you'll need it for the secret.

### 2.2 Generate Private Key

Scroll down to the **Private keys** section.

1. Click **Generate a private key**
2. A `.pem` file will automatically download to your computer
3. **Keep this file safe** - you'll need it in the next step

The file will be named something like:
```
renovate-bot-homelab.2025-10-21.private-key.pem
```

---

## Step 3: Install the App on Your Repository

### 3.1 Navigate to Installation

On the left sidebar of the app settings page, click **Install App**.

Or go directly to:
```
https://github.com/apps/renovate-bot-homelab/installations/new
```
(Replace `renovate-bot-homelab` with your app name)

### 3.2 Select Installation Target

You'll see your GitHub account. Click the **Install** button next to it.

### 3.3 Choose Repository Access

You'll be asked where to install this app:

- ⚪ All repositories (not recommended)
- ⚪ **Only select repositories** ← Choose this

In the dropdown, select:
- ✅ **plpetkov-tech/homelab**

### 3.4 Complete Installation

Click the green **Install** button.

---

## Step 4: Add Secrets to Repository

Now we need to add the App ID and Private Key to your repository as secrets.

### 4.1 Open Repository Secrets Settings

Go to:
```
https://github.com/plpetkov-tech/homelab/settings/secrets/actions
```

Or manually:
1. Go to your repository: `https://github.com/plpetkov-tech/homelab`
2. Click **Settings** tab
3. In the left sidebar, click **Secrets and variables**
4. Click **Actions**
5. You should see "Actions secrets" page

### 4.2 Add First Secret: App ID

1. Click **New repository secret** (green button)
2. Fill in:
   - **Name**: `RENOVATE_APP_ID`
   - **Secret**: Paste the App ID from Step 2.1 (e.g., `123456`)
3. Click **Add secret**

### 4.3 Add Second Secret: Private Key

1. Click **New repository secret** again
2. **Name**: `RENOVATE_APP_PRIVATE_KEY`
3. **Secret**: Open the `.pem` file you downloaded in Step 2.2

**How to get the private key content**:

**On Linux/Mac**:
```bash
cat ~/Downloads/renovate-bot-homelab.*.private-key.pem
```

**On Windows**:
- Open the `.pem` file with Notepad
- Select all (Ctrl+A)
- Copy (Ctrl+C)

The content should look like:
```
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...
(many lines of random characters)
...
-----END RSA PRIVATE KEY-----
```

4. **Paste the ENTIRE content** into the Secret field (including the BEGIN and END lines)
5. Click **Add secret**

### 4.4 Verify Secrets

You should now see two secrets listed:
- ✅ `RENOVATE_APP_ID`
- ✅ `RENOVATE_APP_PRIVATE_KEY`

---

## Step 5: Push Renovate Configuration

Now let's commit and push all the Renovate files to your repository.

### 5.1 Check Files

Make sure you have these files:
```bash
ls -la /home/plamen/homelab/renovate.json
ls -la /home/plamen/homelab/.github/workflows/renovate.yml
ls -la /home/plamen/homelab/docs/RENOVATE*.md
```

### 5.2 Commit and Push

```bash
cd /home/plamen/homelab

# Stage all Renovate files
git add renovate.json \
        .github/workflows/renovate.yml \
        docs/RENOVATE*.md \
        README.md

# Check what will be committed
git status

# Commit with descriptive message
git commit -m "feat: implement Renovate bot for automated dependency updates

- Add comprehensive Renovate configuration for Helm, Terraform, Docker
- Configure GitHub Actions workflow with GitHub App authentication
- Enable smart grouping and scheduling for updates
- Add auto-merge for stable patch updates
- Pin container images to SHA256 digests for security
- Add complete documentation

Manages 74+ dependencies:
- 17 Helm charts (infrastructure, monitoring, apps)
- 2 Terraform providers (Proxmox, Unifi)
- 6 Flux system components
- Multiple container images

Respects existing Flux image automation for application containers.
"

# Push to GitHub
git push origin main
```

---

## Step 6: Trigger First Renovate Run

### 6.1 Navigate to Actions

Go to:
```
https://github.com/plpetkov-tech/homelab/actions
```

Or click the **Actions** tab in your repository.

### 6.2 Find Renovate Workflow

In the left sidebar, you should see:
- **Renovate** (with a 🤖 or workflow icon)

Click on it.

### 6.3 Run Workflow Manually

1. You'll see a blue banner that says "This workflow has a workflow_dispatch event trigger"
2. Click **Run workflow** (button on the right)
3. A dialog appears:
   - **Branch**: `main` (should be selected)
   - **Dry-Run**: `false` (default)
   - **Log-Level**: `debug` (set to debug for first run)
4. Click the green **Run workflow** button

### 6.4 Monitor Progress

1. The page will refresh and show a workflow run starting
2. Click on the workflow run (it will say "Renovate" with a yellow dot)
3. Click on **Renovate** job to see live logs
4. Wait 2-5 minutes for completion

**What to expect in logs**:
- ✅ "Checkout" step completes
- ✅ "Generate Token" step completes (creates token from your GitHub App)
- ✅ "Renovate" step runs
  - Discovers repositories
  - Clones your repo
  - Extracts dependencies
  - Creates Dependency Dashboard
  - May create PRs

---

## Step 7: Check Results

### 7.1 Look for Dependency Dashboard Issue

1. Go to the **Issues** tab of your repository
2. You should see a new issue: **Dependency Dashboard**
3. Click on it

This issue shows:
- ✅ All detected dependencies
- 📋 Available updates
- ⏸️ Rate-limited or pending updates
- ❌ Any errors

### 7.2 Check for Pull Requests

1. Go to the **Pull Requests** tab
2. You might see PRs with labels:
   - `dependencies`
   - `renovate`

Renovate may create PRs immediately if updates are available, or wait for the scheduled time.

### 7.3 Review First Updates

If PRs were created:

1. Click on a PR
2. Review:
   - What's being updated
   - Version changes
   - Release notes (Renovate includes links)
3. Check if tests pass (if you have CI/CD)
4. Merge when ready

---

## Step 8: Configure Scheduled Runs (Optional)

The workflow is already configured to run automatically at 2am UTC daily. No action needed.

If you want to change the schedule, edit `.github/workflows/renovate.yml`:

```yaml
schedule:
  # Current: Daily at 2am UTC
  - cron: "0 2 * * *"

  # Change to: Daily at 10pm UTC
  # - cron: "0 22 * * *"
```

---

## Verification Checklist

After completing all steps, verify:

- ✅ GitHub App created with correct permissions
- ✅ App installed on `plpetkov-tech/homelab` repository
- ✅ Two secrets added to repository:
  - `RENOVATE_APP_ID`
  - `RENOVATE_APP_PRIVATE_KEY`
- ✅ All files committed and pushed to GitHub
- ✅ Workflow run completed successfully
- ✅ Dependency Dashboard issue created
- ✅ Renovate discovers dependencies

---

## Troubleshooting

### Workflow Fails with "Bad credentials"

**Cause**: Secrets are incorrect or not set

**Fix**:
1. Check secrets in repository settings
2. Verify `RENOVATE_APP_ID` matches the App ID
3. Verify `RENOVATE_APP_PRIVATE_KEY` contains the complete `.pem` file content
4. Re-run the workflow

### Workflow Fails with "Resource not accessible by integration"

**Cause**: GitHub App doesn't have correct permissions

**Fix**:
1. Go to GitHub App settings
2. Check **Repository permissions**:
   - Contents: Read and write
   - Pull requests: Read and write
   - Issues: Read and write
   - Workflows: Read and write
3. Save changes
4. Re-run the workflow

### No Dependency Dashboard Created

**Cause**: Renovate might not have found any dependencies, or failed to create the issue

**Fix**:
1. Check workflow logs for errors
2. Run workflow with `logLevel: debug`
3. Look for "Dependency extraction" in logs
4. Verify `renovate.json` is valid:
   ```bash
   renovate-config-validator
   ```

### Workflow Doesn't Appear in Actions Tab

**Cause**: Workflow file not in correct location or has syntax errors

**Fix**:
1. Verify file exists: `.github/workflows/renovate.yml`
2. Check file is on `main` branch
3. Validate YAML syntax:
   ```bash
   yamllint .github/workflows/renovate.yml
   ```

---

## Next Steps

Once Renovate is running successfully:

1. **Review the Dependency Dashboard** weekly
2. **Merge PRs** as they come in (respecting the schedule)
3. **Customize** `renovate.json` as needed:
   - Add more packages to auto-merge
   - Adjust schedules
   - Change grouping rules
4. **Monitor** for security updates (high priority PRs)

---

## Support

- **Full Documentation**: [RENOVATE.md](./RENOVATE.md)
- **Quick Reference**: [RENOVATE-QUICKSTART.md](./RENOVATE-QUICKSTART.md)
- **Renovate Docs**: https://docs.renovatebot.com/
- **Renovate Discord**: https://discord.gg/renovate

---

## Summary

You've successfully:
- ✅ Created a GitHub App for Renovate
- ✅ Installed it on your repository
- ✅ Added secrets for authentication
- ✅ Pushed Renovate configuration
- ✅ Triggered first run
- ✅ Verified Dependency Dashboard creation

Renovate will now automatically:
- Run daily at 2am UTC
- Create grouped PRs for updates
- Auto-merge safe patch updates
- Alert you to security vulnerabilities
- Keep your 74+ dependencies up-to-date

**Congratulations! Your homelab is now using automated dependency management.** 🎉
