#!/usr/bin/env bash
set -euo pipefail

# Public bootstrap script; all real logic lives in `dev`.

REPO="kurtkuehnert/dev-setup"
DIR="$HOME/dev-setup"

info() { printf '\033[1;34m%s\033[0m\n' "$1"; }
error() { printf '\033[1;31m%s\033[0m\n' "$1"; exit 1; }

brew_bin() {
    command -v brew 2>/dev/null && return 0
    [ -x /opt/homebrew/bin/brew ] && { echo /opt/homebrew/bin/brew; return 0; }
    [ -x /usr/local/bin/brew ] && { echo /usr/local/bin/brew; return 0; }
    return 1
}

ensure_brew() {
    brew_bin &>/dev/null && return 0
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew_bin &>/dev/null || error "Homebrew installed, but brew was not found."
}

gh_bin() {
    command -v gh 2>/dev/null && return 0
    [ -x /opt/homebrew/bin/gh ] && { echo /opt/homebrew/bin/gh; return 0; }
    [ -x /usr/local/bin/gh ] && { echo /usr/local/bin/gh; return 0; }
    [ -x /usr/bin/gh ] && { echo /usr/bin/gh; return 0; }
    return 1
}

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
            ensure_brew
            "$(brew_bin)" install gh ;;
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

gh_bin &>/dev/null || install_gh
GH="$(gh_bin)" || error "gh installed, but gh was not found."

# Authenticate for private repo access (opens browser)
if ! "$GH" auth status &>/dev/null 2>&1; then
    info "Authenticating with GitHub..."
    "$GH" auth login -w -s repo
fi
"$GH" auth setup-git --hostname github.com

# Clone private repo via gh, hand off to dev
info "Cloning dev-setup..."
git clone "https://github.com/$REPO.git" "$DIR"
"$DIR/dev" pull -u
