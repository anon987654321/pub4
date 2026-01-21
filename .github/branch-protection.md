# Recommended Branch Protection Settings

Go to Settings → Branches → Add rule for `main`:

## Required Settings

- [x] Require a pull request before merging
- [x] Require status checks to pass before merging
  - [x] test
  - [x] lint
  - [x] secrets
- [x] Require conversation resolution before merging
- [x] Do not allow bypassing the above settings

## Optional Settings

- [ ] Require approvals (set to 1 if team grows)
- [x] Dismiss stale PR approvals when new commits are pushed
- [x] Require branches to be up to date before merging

## To Apply

```zsh
gh api repos/anon987654321/pub4/branches/main/protection \
  -X PUT \
  -H "Accept: application/vnd.github+json" \
  -f required_status_checks='{"strict":true,"contexts":["test","lint","secrets"]}' \
  -f enforce_admins=true \
  -f required_pull_request_reviews='{"required_approving_review_count":0}' \
  -f restrictions=null
```
