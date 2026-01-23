# jj workspace management functions
# Manages jj repos in ~/repos/ and workspaces in ~/trees/ with tmux integration

REPOS_DIR="$HOME/repos"
TREES_DIR="$HOME/trees"

repo-clone() {
    if [ -z "$1" ]; then
        echo "Usage: repo-clone <url>"
        return 1
    fi
    local url="$1"
    local name="${2:-$(basename "$url" .git)}"
    local repo_path="$REPOS_DIR/$name"

    mkdir -p "$REPOS_DIR"

    if [ -d "$repo_path" ]; then
        echo "Repo already exists: $repo_path"
        return 1
    fi

    jj git clone --colocate "$url" "$repo_path"
}

tree-new() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: tree-new <repo> <name> [base-rev]"
        echo "  repo: name of repo in ~/repos/"
        echo "  name: name for the tree/branch"
        echo "  base-rev: revision to branch from (default: trunk())"
        return 1
    fi
    local repo="$1"
    local name="$2"
    local base_rev="${3:-trunk()}"
    local repo_path="$REPOS_DIR/$repo"
    local tree_name="$repo-$name"
    local tree_path="$TREES_DIR/$tree_name"

    if [ ! -d "$repo_path" ]; then
        echo "Repo not found: $repo_path"
        return 1
    fi

    if [ -d "$tree_path" ]; then
        echo "Tree already exists: $tree_path"
        return 1
    fi

    mkdir -p "$TREES_DIR"

    # Create workspace at base revision
    jj -R "$repo_path" workspace add "$tree_path" --name "$tree_name" -r "$base_rev"

    # Create new change and bookmark
    jj -R "$tree_path" new -m "$name"
    jj -R "$tree_path" bookmark create "$name"

    # Create and attach to tmux session
    if tmux has-session -t "$tree_name" 2>/dev/null; then
        tmux attach -t "$tree_name"
    else
        tmux new-session -s "$tree_name" -c "$tree_path"
    fi
}

tree-open() {
    if [ -z "$1" ]; then
        echo "Usage: tree-open <name>"
        echo "  name: full tree name (repo-branch) or partial match"
        tree-list
        return 1
    fi
    local name="$1"
    local tree_path="$TREES_DIR/$name"

    # Try exact match first
    if [ ! -d "$tree_path" ]; then
        # Try to find a match
        local matches=("$TREES_DIR"/*"$name"*(N))
        if [ ${#matches[@]} -eq 0 ]; then
            echo "No tree found matching: $name"
            tree-list
            return 1
        elif [ ${#matches[@]} -gt 1 ]; then
            echo "Multiple matches found:"
            printf '  %s\n' "${matches[@]##*/}"
            return 1
        fi
        tree_path="${matches[1]}"
        name="$(basename "$tree_path")"
    fi

    # Create or attach to tmux session
    if tmux has-session -t "$name" 2>/dev/null; then
        tmux attach -t "$name"
    else
        tmux new-session -s "$name" -c "$tree_path"
    fi
}

tree-list() {
    echo "Workspaces:"
    for repo_path in "$REPOS_DIR"/*(N/); do
        local repo="$(basename "$repo_path")"
        if [ -d "$repo_path/.jj" ]; then
            echo "  $repo:"
            jj -R "$repo_path" workspace list 2>/dev/null | while read -r line; do
                local ws_name="${line%%:*}"
                local tmux_status=""
                if tmux has-session -t "$ws_name" 2>/dev/null; then
                    tmux_status=" [tmux]"
                fi
                echo "    $line$tmux_status"
            done
        fi
    done
}

tree-rm() {
    if [ -z "$1" ]; then
        echo "Usage: tree-rm <name>"
        return 1
    fi
    local name="$1"
    local tree_path="$TREES_DIR/$name"

    if [ ! -d "$tree_path" ]; then
        echo "Tree not found: $tree_path"
        return 1
    fi

    # Find the repo this workspace belongs to
    local repo_path
    repo_path="$(jj -R "$tree_path" workspace root 2>/dev/null)"

    if [ -z "$repo_path" ]; then
        echo "Could not determine repo for workspace"
        return 1
    fi

    # Kill tmux session if running
    if tmux has-session -t "$name" 2>/dev/null; then
        echo "Killing tmux session: $name"
        tmux kill-session -t "$name"
    fi

    # Forget the workspace in jj
    echo "Forgetting workspace: $name"
    jj -R "$repo_path" workspace forget "$name"

    # Remove the directory
    echo "Removing directory: $tree_path"
    rm -rf "$tree_path"

    echo "Done."
}
