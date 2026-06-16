# dev-bootstrap

Public, fetch-without-auth mirror of the Beli one-command dev-machine bootstrap.

```bash
curl -fsSL https://raw.githubusercontent.com/Beli-Technologies/dev-bootstrap/master/bootstrap.sh | bash
```

## ⚠️ Do not edit this repo directly

`bootstrap.sh` is **auto-generated**. The source of truth is
`dev-setup/bootstrap.sh` in the private `Beli-Technologies/bellibackend` repo,
which mirrors it here via `.github/workflows/sync-bootstrap.yml` on every push
to `master`. Edits made directly here will be overwritten on the next sync.

This repo is public **only** so a brand-new Mac (no Homebrew, no GitHub auth)
can fetch the entry-point script. It contains no secrets — the script clones the
private repos only *after* running `gh auth login`.
