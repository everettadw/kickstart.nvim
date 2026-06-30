#!/usr/bin/env bash
set -euo pipefail

echo "==> Detecting OS..."
OS="$(uname -s)"
ARCH="$(uname -m)"

echo "OS: $OS"
echo "ARCH: $ARCH"

# =========================
# User-configurable settings
# =========================

DOTFILES_REPO="https://github.com/everettadw/dotfiles.git"
DOTFILES_DIR="$HOME/dotfiles"
USE_SYMLINKS="true"

# Expected repo layout:
#
# ~/dotfiles/
# ├── nvim/
# │   └── init.lua
# ├── starship/
# │   └── starship.toml
# ├── wezterm/
# │   └── wezterm.lua
# └── zsh/
#     └── .zshrc

# =========================
# Helpers
# =========================

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

apt_install_if_missing() {
  local cmd="$1"
  shift

  local packages=("$@")

  if has_cmd "$cmd"; then
    echo "==> $cmd already installed. Skipping."
  else
    echo "==> Installing ${packages[*]}..."
    sudo apt install -y "${packages[@]}"
  fi
}

brew_install_if_missing() {
  local cmd="$1"
  shift

  local packages=("$@")

  if has_cmd "$cmd"; then
    echo "==> $cmd already installed. Skipping."
  else
    echo "==> Installing ${packages[*]}..."
    brew install "${packages[@]}"
  fi
}

brew_cask_install_if_missing() {
  local cmd="$1"
  local cask="$2"

  if has_cmd "$cmd"; then
    echo "==> $cmd already installed. Skipping."
  else
    echo "==> Installing $cask..."
    brew install --cask "$cask"
  fi
}

# =========================
# Linux install
# =========================

install_linux() {
  echo "==> Updating apt..."
  sudo apt update

  echo "==> Installing base dependencies..."
  sudo apt install -y \
    git \
    curl \
    unzip \
    build-essential \
    gcc \
    g++ \
    make \
    clang

  apt_install_if_missing zsh zsh
  apt_install_if_missing node nodejs npm
  apt_install_if_missing npm npm
  apt_install_if_missing rg ripgrep
  apt_install_if_missing zoxide zoxide

  echo "==> Checking eza..."
  if has_cmd eza; then
    echo "==> eza already installed. Skipping."
  else
    if sudo apt install -y eza; then
      echo "==> eza installed from apt."
    else
      echo "==> apt could not install eza. Will try cargo after Rust is installed."
      NEED_EZA_CARGO="true"
    fi
  fi

  echo "==> Checking Neovim..."
  if has_cmd nvim; then
    echo "==> Neovim already installed:"
    nvim --version | head -n 1
  else
    install_neovim_appimage_linux
  fi
}

install_neovim_appimage_linux() {
  echo "==> Installing latest Neovim AppImage..."

  cd /tmp
  rm -f nvim-linux-x86_64.appimage nvim-linux-arm64.appimage

  if [[ "$ARCH" == "x86_64" ]]; then
    NVIM_APPIMAGE="nvim-linux-x86_64.appimage"
  elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    NVIM_APPIMAGE="nvim-linux-arm64.appimage"
  else
    echo "Unsupported architecture for Neovim AppImage: $ARCH"
    exit 1
  fi

  curl -fLO "https://github.com/neovim/neovim/releases/latest/download/$NVIM_APPIMAGE"
  chmod u+x "$NVIM_APPIMAGE"
  sudo mv "$NVIM_APPIMAGE" /usr/local/bin/nvim

  echo "==> Neovim installed:"
  nvim --version | head -n 1
}

install_starship_linux() {
  echo "==> Checking Starship..."

  if has_cmd starship; then
    echo "==> Starship already installed. Skipping."
  else
    echo "==> Installing Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  fi
}

install_rust_linux() {
  echo "==> Checking Rust/rustup..."

  if has_cmd rustup && has_cmd cargo; then
    echo "==> Rust/rustup already installed. Updating stable toolchain..."
  else
    echo "==> Installing Rust with rustup..."
    curl https://sh.rustup.rs -sSf | sh -s -- -y
  fi

  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"

  rustup install stable
  rustup default stable
}

install_tree_sitter_linux() {
  echo "==> Checking tree-sitter-cli..."

  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"

  if has_cmd tree-sitter; then
    echo "==> tree-sitter already installed. Skipping."
  else
    echo "==> Installing tree-sitter-cli..."
    cargo install --locked tree-sitter-cli
  fi
}

install_eza_with_cargo_if_needed() {
  if [[ "${NEED_EZA_CARGO:-false}" == "true" ]] && ! has_cmd eza; then
    echo "==> Installing eza with cargo..."

    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"

    cargo install eza
  fi
}

# =========================
# macOS install
# =========================

install_macos() {
  echo "==> Checking Homebrew..."

  if ! has_cmd brew; then
    echo "==> Homebrew not found. Installing Homebrew..."

    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    echo "==> Adding Homebrew to PATH for this script..."

    if [[ -x "/opt/homebrew/bin/brew" ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x "/usr/local/bin/brew" ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    else
      echo "Homebrew install finished, but brew was not found in the expected location."
      echo "Open a new terminal session and run this script again."
      exit 1
    fi
  else
    echo "==> Homebrew already installed."
  fi

  echo "==> Updating Homebrew..."
  brew update

  brew_install_if_missing zsh zsh
  brew_install_if_missing starship starship
  brew_install_if_missing nvim neovim
  brew_install_if_missing rg ripgrep
  brew_install_if_missing zoxide zoxide
  brew_install_if_missing eza eza
  brew_install_if_missing tree-sitter tree-sitter-cli
  brew_install_if_missing node node

  echo "==> Checking Rust/Cargo..."
  if has_cmd cargo && has_cmd rustup; then
    echo "==> Rust/Cargo already installed. Skipping rustup-init."
  else
    brew_install_if_missing rustup-init rustup-init
    rustup-init -y

    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
  fi

  brew_cask_install_if_missing wezterm wezterm
}

# =========================
# Dotfiles setup
# =========================

setup_dotfiles() {
  echo "==> Setting up dotfiles..."

  if [[ "$DOTFILES_REPO" == "https://github.com/YOUR_USERNAME/YOUR_REPO.git" ]]; then
    echo "DOTFILES_REPO is still set to the placeholder."
    echo "Edit the script and set DOTFILES_REPO to your actual GitHub repo URL."
    exit 1
  fi

  if [[ -d "$DOTFILES_DIR/.git" ]]; then
    echo "==> Dotfiles repo already exists. Pulling latest changes..."
    git -C "$DOTFILES_DIR" pull --ff-only
  else
    echo "==> Cloning dotfiles repo..."
    git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
  fi

  backup_path() {
    local target="$1"

    if [[ -e "$target" || -L "$target" ]]; then
      local backup="${target}.bak.$(date +%Y%m%d%H%M%S)"
      echo "==> Backing up $target to $backup"
      mv "$target" "$backup"
    fi
  }

  link_or_copy() {
    local source="$1"
    local target="$2"

    if [[ ! -e "$source" ]]; then
      echo "==> Skipping missing source: $source"
      return
    fi

    mkdir -p "$(dirname "$target")"
    backup_path "$target"

    if [[ "$USE_SYMLINKS" == "true" ]]; then
      echo "==> Symlinking $source -> $target"
      ln -s "$source" "$target"
    else
      echo "==> Copying $source -> $target"
      cp -R "$source" "$target"
    fi
  }

  link_or_copy "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
  link_or_copy "$DOTFILES_DIR/starship/starship.toml" "$HOME/.config/starship.toml"
  link_or_copy "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"

  if [[ "$OS" == "Darwin" ]]; then
    link_or_copy "$DOTFILES_DIR/wezterm" "$HOME/.config/wezterm"
  fi
}

# =========================
# Shell setup
# =========================

set_default_shell_to_zsh() {
  echo "==> Setting zsh as the default shell..."

  ZSH_PATH="$(command -v zsh)"

  if [[ -z "$ZSH_PATH" ]]; then
    echo "zsh was not found on PATH."
    exit 1
  fi

  if [[ -f /etc/shells ]] && ! grep -qxF "$ZSH_PATH" /etc/shells; then
    echo "==> Adding $ZSH_PATH to /etc/shells..."
    echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
  fi

  CURRENT_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || true)"

  # macOS does not usually have getent.
  if [[ -z "$CURRENT_SHELL" && "$OS" == "Darwin" ]]; then
    CURRENT_SHELL="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}' || true)"
  fi

  if [[ "$CURRENT_SHELL" != "$ZSH_PATH" ]]; then
    echo "==> Changing default shell for $USER to $ZSH_PATH..."
    chsh -s "$ZSH_PATH"
  else
    echo "==> zsh is already the default shell."
  fi
}

# =========================
# Verification
# =========================

verify_installs() {
  echo
  echo "==> Verifying installs..."

  command -v zsh >/dev/null 2>&1 && zsh --version
  command -v starship >/dev/null 2>&1 && starship --version
  command -v nvim >/dev/null 2>&1 && nvim --version | head -n 1
  command -v rg >/dev/null 2>&1 && rg --version | head -n 1
  command -v zoxide >/dev/null 2>&1 && zoxide --version
  command -v eza >/dev/null 2>&1 && eza --version | head -n 1
  command -v tree-sitter >/dev/null 2>&1 && tree-sitter --version

  if command -v cargo >/dev/null 2>&1; then
    cargo --version
  fi

  if command -v rustc >/dev/null 2>&1; then
    rustc --version
  fi

  if command -v node >/dev/null 2>&1; then
    node --version
  fi

  if command -v npm >/dev/null 2>&1; then
    npm --version
  fi

  if [[ "$OS" == "Darwin" ]]; then
    command -v wezterm >/dev/null 2>&1 && wezterm --version
  fi
}

# =========================
# Main
# =========================

main() {
  if [[ "$OS" == "Linux" ]]; then
    install_linux
    install_starship_linux
    install_rust_linux
    install_tree_sitter_linux
    install_eza_with_cargo_if_needed
  elif [[ "$OS" == "Darwin" ]]; then
    install_macos
  else
    echo "Unsupported OS for this bash script: $OS"
    exit 1
  fi

  setup_dotfiles
  set_default_shell_to_zsh
  verify_installs

  echo
  echo "==> Done."
  echo "zsh has been set as your default shell."
  echo "Your existing terminal session may still be running the old shell until you open a new session or log out and back in."
}

main
