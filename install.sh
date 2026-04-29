#!/usr/bin/env bash
set -euo pipefail

# Public bootstrap script; all real logic lives in `dev`.

REPO="kurtkuehnert/dev-setup"
DIR="$HOME/dev-setup"

info() { printf '\033[1;34m%s\033[0m\n' "$1"; }
error() { printf '\033[1;31m%s\033[0m\n' "$1"; exit 1; }

# Already installed — just pull
if [ -d "$DIR" ] && { [ -d "$DIR/.jj" ] || [ -d "$DIR/.git" ]; }; then
    info "dev-setup already installed, running pull..."
    exec "$DIR/dev" pull -u
fi

# --- Bootstrap gh (needed to clone private repo) ---

install_gh() {
    info "Installing gh..."
    case "$(uname -s)" in
        Darwin)
            if ! command -v brew &>/dev/null; then
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
            fi
            brew install gh ;;
        Linux)
            if command -v dnf &>/dev/null; then
                sudo dnf install -y gh
            elif command -v apt-get &>/dev/null; then
                sudo mkdir -p -m 755 /etc/apt/keyrings
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
                sudo apt-get update -y
                sudo apt-get install -y gh
            else
                error "Install gh manually, then re-run."
            fi ;;
        *) error "Unsupported OS" ;;
    esac
}

command -v gh &>/dev/null || install_gh

# Authenticate for private repo access (opens browser)
if ! gh auth status &>/dev/null 2>&1; then
    info "Authenticating with GitHub..."
    gh auth login -w -s repo
fi
gh auth setup-git --hostname github.com

# Clone private repo via gh, hand off to dev
info "Cloning dev-setup..."
git clone "https://github.com/$REPO.git" "$DIR"
"$DIR/dev" pull -u
