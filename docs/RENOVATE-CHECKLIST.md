# Renovate Setup Checklist

Follow these steps in order. Check off each item as you complete it.

## Part 1: Create GitHub App (5 minutes)

### Step 1: Create the App
- [ ] Go to https://github.com/settings/apps/new
- [ ] Fill in:
  - **Name**: `Renovate Bot - Homelab` (or similar if taken)
  - **Homepage URL**: `https://github.com/plpetkov-tech/homelab`
  - **Webhook**: Uncheck "Active"
- [ ] Set Repository Permissions:
  - **Contents**: Read and write
  - **Pull requests**: Read and write
  - **Issues**: Read and write
  - **Workflows**: Read and write
- [ ] Select: "Only on this account"
- [ ] Click "Create GitHub App"

### Step 2: Get Credentials
- [ ] Copy the **App ID** (shown at top of page)
  - Write it down: `_________________`
- [ ] Scroll to "Private keys" section
- [ ] Click "Generate a private key"
- [ ] Save the downloaded `.pem` file

### Step 3: Install the App
- [ ] Click "Install App" in left sidebar
- [ ] Click "Install" next to your account
- [ ] Select "Only select repositories"
- [ ] Choose `plpetkov-tech/homelab`
- [ ] Click "Install"

## Part 2: Add Secrets to Repository (2 minutes)

- [ ] Go to https://github.com/plpetkov-tech/homelab/settings/secrets/actions
- [ ] Click "New repository secret"
- [ ] Add first secret:
  - Name: `RENOVATE_APP_ID`
  - Secret: (paste the App ID from Step 2)
- [ ] Click "Add secret"
- [ ] Click "New repository secret" again
- [ ] Add second secret:
  - Name: `RENOVATE_APP_PRIVATE_KEY`
  - Secret: (paste the ENTIRE content of the `.pem` file)
- [ ] Click "Add secret"
- [ ] Verify both secrets appear in the list

## Part 3: Push Configuration (1 minute)

Run these commands:

```bash
cd /home/plamen/homelab

# Stage files
git add renovate.json .github/workflows/renovate.yml docs/RENOVATE*.md README.md RENOVATE-CHECKLIST.md

# Commit
git commit -m "feat: implement Renovate bot for automated dependency updates"

# Push
git push origin main
```

- [ ] Commands executed successfully
- [ ] Files pushed to GitHub

## Part 4: Trigger First Run (2 minutes)

- [ ] Go to https://github.com/plpetkov-tech/homelab/actions
- [ ] Click "Renovate" in left sidebar
- [ ] Click "Run workflow" button
- [ ] Set "Log-Level" to `debug`
- [ ] Click green "Run workflow" button
- [ ] Wait for completion (2-5 minutes)
- [ ] Check that workflow completed successfully (green checkmark)

## Part 5: Verify Results (1 minute)

- [ ] Go to https://github.com/plpetkov-tech/homelab/issues
- [ ] Verify "Dependency Dashboard" issue was created
- [ ] Open the issue and review detected dependencies
- [ ] Check for any Pull Requests in the PR tab

---

## You're Done! 🎉

Renovate is now:
- ✅ Running daily at 2am UTC
- ✅ Monitoring 74+ dependencies
- ✅ Creating grouped PRs for updates
- ✅ Auto-merging safe patches
- ✅ Alerting on security issues

## What's Next?

1. **Review Dependency Dashboard** to see all detected updates
2. **Merge PRs** as they arrive (starting this weekend)
3. **Read full docs** at `docs/RENOVATE-SETUP.md` for details

---

## Quick Links

- **Detailed Setup Guide**: [docs/RENOVATE-SETUP.md](docs/RENOVATE-SETUP.md)
- **Full Documentation**: [docs/RENOVATE.md](docs/RENOVATE.md)
- **Quick Reference**: [docs/RENOVATE-QUICKSTART.md](docs/RENOVATE-QUICKSTART.md)
- **Implementation Summary**: [docs/RENOVATE-SUMMARY.md](docs/RENOVATE-SUMMARY.md)

## Support

If you run into issues:
1. Check [docs/RENOVATE-SETUP.md](docs/RENOVATE-SETUP.md) troubleshooting section
2. Review workflow logs in Actions tab
3. Validate config: `renovate-config-validator`

---

**Estimated Total Time**: 10-15 minutes
