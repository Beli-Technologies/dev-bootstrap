#!/usr/bin/env bash
#
# Beli one-shot dev bootstrap — brand-new Mac → fully set up, single command.
#
# On a fresh machine with NOTHING installed (no Homebrew, no git repos):
#
#     curl -fsSL https://raw.githubusercontent.com/Beli-Technologies/dev-bootstrap/master/bootstrap.sh | bash
#
# (That URL is the PUBLIC mirror of this file — bellibackend is private, so its
#  raw URL 404s for someone who hasn't authenticated yet. The mirror is kept in
#  sync from THIS file by .github/workflows/sync-bootstrap.yml; edit it here, not
#  there.)
#
# …or, if you already have this file checked out:
#
#     bash dev-setup/bootstrap.sh
#
# This handles the chicken-and-egg parts that setup.sh can't do on its own —
# installing Claude Code, Homebrew and gh, authenticating to GitHub, and the
# FIRST clone of bellibackend — then hands off to dev-setup/setup.sh, which does
# everything else (brew bundle, the other repos, backend venv, frontend, etc.).
#
# Idempotent: safe to re-run any time to repair a broken environment.
# Override the workspace root with:  BELI_DIR=~/code/beli bash dev-setup/bootstrap.sh
set -euo pipefail

# ---------------------------------------------------------------------------
# config
# ---------------------------------------------------------------------------
GH_ORG="Beli-Technologies"
BOOTSTRAP_REPO="bellibackend"          # the repo that carries dev-setup/setup.sh
BELI_DIR="${BELI_DIR:-$HOME/Desktop/Beli}"   # workspace root (matches setup.sh default)

# ---------------------------------------------------------------------------
# pretty logging (mirrors setup.sh)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then BOLD=$'\033[1m'; BLUE=$'\033[34m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else BOLD=""; BLUE=""; GREEN=""; YELLOW=""; RED=""; RESET=""; fi
step()  { echo; echo "${BOLD}${BLUE}==> $*${RESET}"; }
ok()    { echo "${GREEN}  ✓ $*${RESET}"; }
warn()  { echo "${YELLOW}  ! $*${RESET}"; }
die()   { echo "${RED}  ✗ $*${RESET}" >&2; exit 1; }
have()  { command -v "$1" >/dev/null 2>&1; }

# Append a line to a shell rc file only if it isn't already there (idempotent).
add_line() { # add_line <file> <line>
  local file="$1" line="$2"
  touch "$file"
  grep -qsF -- "$line" "$file" || { echo "$line" >> "$file"; ok "added to ${file/#$HOME/~}: $line"; }
}

# A tty we can read interactive prompts from even when piped via `curl | bash`.
TTY="/dev/tty"
[[ -e "$TTY" ]] || TTY=""

# ---------------------------------------------------------------------------
# 0. preflight
# ---------------------------------------------------------------------------
step "Preflight"
[[ "$(uname -s)" == "Darwin" ]] || die "This script targets macOS."
ARCH="$(uname -m)"
ok "macOS $(sw_vers -productVersion) on $ARCH"
echo "  Workspace root : $BELI_DIR"

# ---------------------------------------------------------------------------
# 1. Claude Code
# ---------------------------------------------------------------------------
step "Claude Code"
if have claude; then
  ok "claude already installed ($(claude --version 2>/dev/null | head -1 || echo present))"
else
  warn "installing Claude Code …"
  curl -fsSL https://claude.ai/install.sh | bash
  # the installer drops the binary in ~/.local/bin — make sure it's on PATH now + in future shells
  export PATH="$HOME/.local/bin:$PATH"
  # shellcheck disable=SC2016  # we want the literal $HOME written into .zshrc, not expanded now
  add_line "$HOME/.zshrc" 'export PATH="$HOME/.local/bin:$PATH"'
  if have claude; then ok "claude installed"; else warn "claude not on PATH yet — open a new terminal after this finishes"; fi
fi

# ---------------------------------------------------------------------------
# 2. Homebrew
# ---------------------------------------------------------------------------
step "Homebrew"
if ! have brew; then
  warn "Homebrew not found — installing (you may be prompted for your password once) …"
  # macOS 26+ sets timestamp_timeout=0 so every sudo call prompts. Temporarily
  # grant NOPASSWD for this user so Homebrew's install only needs one prompt,
  # then remove it immediately after. The trap ensures cleanup even on failure.
  echo "$(whoami) ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/homebrew_install >/dev/null
  trap 'sudo rm -f /etc/sudoers.d/homebrew_install 2>/dev/null' EXIT
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  sudo rm -f /etc/sudoers.d/homebrew_install
  trap - EXIT
fi
# Resolve brew for this session (arm64 → /opt/homebrew, Intel → /usr/local) and persist it.
if   [[ -x /opt/homebrew/bin/brew ]]; then BREW_BIN=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew   ]]; then BREW_BIN=/usr/local/bin/brew
else die "Homebrew install failed — brew binary not found."; fi
eval "$("$BREW_BIN" shellenv)"
add_line "$HOME/.zprofile" "eval \"\$($BREW_BIN shellenv)\""
ok "brew $(brew --version | head -1 | awk '{print $2}')"

# ---------------------------------------------------------------------------
# 3. GitHub CLI (just enough to clone — setup.sh's brew bundle installs the rest)
# ---------------------------------------------------------------------------
step "GitHub CLI"
if ! have gh; then
  warn "installing gh …"
  brew install gh
fi
ok "gh $(gh --version | head -1 | awk '{print $3}')"

# ---------------------------------------------------------------------------
# 4. GitHub auth
# ---------------------------------------------------------------------------
step "GitHub auth"
if gh auth status >/dev/null 2>&1; then
  ok "gh authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')"
elif [[ -n "$TTY" ]]; then
  warn "launching 'gh auth login' (choose: GitHub.com → HTTPS → authenticate via browser) …"
  gh auth login --hostname github.com --git-protocol https --web < "$TTY" || die "gh auth login did not complete."
  ok "authenticated as $(gh api user --jq .login 2>/dev/null || echo '?')"
else
  die "Not authenticated and no terminal available. Run 'gh auth login' yourself, then re-run this script."
fi

# ---------------------------------------------------------------------------
# 5. First clone: bellibackend (carries dev-setup/setup.sh)
# ---------------------------------------------------------------------------
step "Clone $BOOTSTRAP_REPO"
mkdir -p "$BELI_DIR"
BACKEND_DIR="$BELI_DIR/$BOOTSTRAP_REPO"
if [[ -d "$BACKEND_DIR/.git" ]]; then
  ok "$BOOTSTRAP_REPO already cloned at $BACKEND_DIR"
else
  echo "  cloning $GH_ORG/$BOOTSTRAP_REPO → $BACKEND_DIR …"
  gh repo clone "$GH_ORG/$BOOTSTRAP_REPO" "$BACKEND_DIR" || die "clone failed (need a repo invite?)"
  ok "cloned"
fi

# ---------------------------------------------------------------------------
# 6. Hand off to the main setup script
# ---------------------------------------------------------------------------
step "Handing off to dev-setup/setup.sh"
[[ -x "$BACKEND_DIR/dev-setup/setup.sh" ]] || die "dev-setup/setup.sh missing in the clone."
echo "  (brew bundle → clone other repos → backend venv → frontend → VSCode → cache agent)"
echo
exec env BELI_DIR="$BELI_DIR" "$BACKEND_DIR/dev-setup/setup.sh"
