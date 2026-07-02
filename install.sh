#!/usr/bin/env bash
set -euo pipefail

# Public bootstrap script; all real logic lives in `dev`.

REPO="kurtkuehnert/dev-setup"
DIR="$HOME/kurtkuehnert/projects/dev-setup"
VAULT="${PROTON_PASS_VAULT:-Dev Setup}"
SESSION_DIR="${PROTON_PASS_SESSION_DIR:-$HOME/.local/state/proton-pass/dev-id}"

info() { printf '\033[1;34m%s\033[0m\n' "$1"; }
error() { printf '\033[1;31m%s\033[0m\n' "$1"; exit 1; }

brew_bin() {
    command -v brew 2>/dev/null && return 0
    [ -x /opt/homebrew/bin/brew ] && { echo /opt/homebrew/bin/brew; return 0; }
    [ -x /usr/local/bin/brew ] && { echo /usr/local/bin/brew; return 0; }
    return 1
}

real_bin() {
    local name="$1" shim candidate candidate_path
    shim="$(realpath "$HOME/.local/bin/$name" 2>/dev/null || true)"

    while IFS= read -r candidate; do
        candidate_path="$(realpath "$candidate" 2>/dev/null || true)"
        if [ -n "$candidate_path" ] && [ "$candidate_path" != "$shim" ] && [ -x "$candidate_path" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done < <(type -P -a "$name" 2>/dev/null || true)

    for candidate in "/opt/homebrew/bin/$name" "/usr/local/bin/$name" "/usr/bin/$name"; do
        [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
    done

    return 1
}

ensure_brew() {
    brew_bin &>/dev/null && return 0
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    brew_bin &>/dev/null || error "Homebrew installed, but brew was not found."
}

brew_install_missing() {
    local name="$1" command_name="${2:-$1}"
    real_bin "$command_name" >/dev/null && return 0
    "$(brew_bin)" install "$name"
}

ensure_bootstrap_deps() {
    info "Checking bootstrap dependencies..."
    case "$(uname -s)" in
        Darwin)
            ensure_brew
            brew_install_missing gh gh
            brew_install_missing git git
            brew_install_missing pass-cli pass-cli ;;
        Linux)
            if command -v dnf &>/dev/null; then
                sudo dnf install -y gh git curl
            elif command -v apt-get &>/dev/null; then
                sudo apt-get update -y
                sudo apt-get install -y gh git curl
            else
                error "Install gh, git, curl, and pass-cli manually, then re-run."
            fi
            command -v pass-cli >/dev/null || curl -fsSL https://proton.me/download/pass-cli/install.sh | bash ;;
        *) error "Unsupported OS" ;;
    esac

    real_bin gh >/dev/null || error "gh is missing after bootstrap dependency install."
    real_bin git >/dev/null || error "git is missing after bootstrap dependency install."
    command -v pass-cli >/dev/null || error "pass-cli is missing after bootstrap dependency install."
}

ensure_proton_login() {
    export PROTON_PASS_SESSION_DIR="$SESSION_DIR"
    mkdir -p "$PROTON_PASS_SESSION_DIR"

    if pass-cli info >/dev/null 2>&1; then
        return 0
    fi

    pass-cli logout >/dev/null 2>&1 || true
    rm -rf "$PROTON_PASS_SESSION_DIR"
    mkdir -p "$PROTON_PASS_SESSION_DIR"

    if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
        error "Proton Pass login is required, but no TTY is available."
    fi

    info "Authenticating Proton Pass..."
    printf 'Paste Proton Pass PAT (pst_...::...): ' > /dev/tty
    IFS= read -r -s proton_pat < /dev/tty
    printf '\n' > /dev/tty
    [ -n "$proton_pat" ] || error "No Proton Pass PAT entered."

    pass-cli login --pat "$proton_pat" >/dev/null
}

pass_field() {
    local item="$1" field="$2"
    PROTON_PASS_AGENT_REASON="Load $item/$field for dev-setup install" \
        pass-cli item view --vault-name "$VAULT" --item-title "$item" --field "$field"
}

export_github_token() {
    local token
    token="$(pass_field "GitHub kurtkuehnert" token)" || error "Missing Proton item field: GitHub kurtkuehnert/token"
    [ -n "$token" ] || error "Empty Proton item field: GitHub kurtkuehnert/token"
    export GH_TOKEN="$token"
    export GITHUB_TOKEN="$token"
}

clone_or_update_repo() {
    if [ -d "$DIR/.git" ] || [ -d "$DIR/.jj" ]; then
        info "dev-setup already installed."
        return 0
    fi

    if [ -e "$DIR" ]; then
        if [ -z "$(find "$DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
            rmdir "$DIR"
        else
            error "$DIR exists but is not a dev-setup checkout; refusing to overwrite it."
        fi
    fi

    mkdir -p "$(dirname "$DIR")"
    info "Cloning dev-setup..."
    "$(real_bin gh)" repo clone "$REPO" "$DIR"
}

ensure_bootstrap_deps
ensure_proton_login
export_github_token
clone_or_update_repo

exec "$DIR/dev" pull
