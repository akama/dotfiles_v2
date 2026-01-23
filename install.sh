#!/bin/bash

set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
SKIP_DIRS=".git"

echo "Installing dotfiles from $DOTFILES_DIR"

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
    done
done

echo "Done!"
