#!/bin/bash

set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
SKIP_DIRS=".git"
DEPENDENCIES="zsh sqlite3 tmux vim git tar make fzf jj age"

echo "Checking that current shell is zsh..."
if [ "$SHELL" != "$(command -v zsh)" ]; then
    echo "Current shell is $SHELL, but zsh is required."
    echo "Run 'sudo usermod -s /usr/bin/zsh \$USER' to set zsh as your default shell."
    exit 1
fi
echo "Shell is zsh."

echo "Checking dependencies..."
missing=""
for dep in $DEPENDENCIES; do
    if ! command -v "$dep" &>/dev/null; then
        missing="$missing $dep"
    fi
done

if [ -n "$missing" ]; then
    echo "Missing dependencies:$missing"
    echo "Install them with your package manager before continuing."
    exit 1
fi
echo "All dependencies found."

echo "Initializing git submodules..."
git -C "$DOTFILES_DIR" submodule update --init --recursive

echo "Creating required directories..."
mkdir -p ~/.vim/undodir
mkdir -p ~/.vim-tmp

echo "Installing dotfiles from $DOTFILES_DIR"

# Source secrets.sh for sync_secret and helpers
source "$DOTFILES_DIR/secrets.sh" --source-only 2>/dev/null || true

for dir in "$DOTFILES_DIR"/*/; do
    dirname="$(basename "$dir")"

    # Skip non-config directories
    [[ " $SKIP_DIRS " =~ " $dirname " ]] && continue

    for item in "$dir"* "$dir".*; do
        # Skip . and ..
        [[ "$(basename "$item")" == "." || "$(basename "$item")" == ".." ]] && continue
        # Skip if glob didn't match anything
        [[ ! -e "$item" ]] && continue

        name="$(basename "$item")"

        if [[ "$name" == *.age ]]; then
            # Decrypt instead of symlink
            plain_name="${name%.age}"
            target="$HOME/$plain_name"
            rel_path="${item#$DOTFILES_DIR/}"
            sync_secret "$item" "$target" "$rel_path" || true
        else
            target="$HOME/$name"

            if [[ -L "$target" ]]; then
                echo "Removing existing symlink: $target"
                rm "$target"
            elif [[ -e "$target" ]]; then
                echo "Backing up existing file: $target -> $target.backup"
                mv "$target" "$target.backup"
            fi

            echo "Linking: $target -> $item"
            ln -s "$item" "$target"
        fi
    done
done

echo "Done!"
