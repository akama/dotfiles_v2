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
    local repo=""
    local name=""
    local base_rev=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--rev|--revision)
                if [ -z "$2" ]; then
                    echo "Missing revision for $1"
                    return 1
                fi
                base_rev="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: tree-new <repo> <name> [-r <base-rev>]"
                echo "  repo: name of repo in ~/repos/"
                echo "  name: name for the tree/branch"
                echo "  -r, --rev: revision to branch from (default: trunk())"
                echo "  example: tree-new myrepo feature -r 'main~3'"
                return 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "Unknown option: $1"
                return 1
                ;;
            *)
                if [ -z "$repo" ]; then
                    repo="$1"
                elif [ -z "$name" ]; then
                    name="$1"
                elif [ -z "$base_rev" ]; then
                    base_rev="$1"
                else
                    echo "Unexpected argument: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [ -z "$repo" ] || [ -z "$name" ]; then
        echo "Usage: tree-new <repo> <name> [-r <base-rev>]"
        echo "  repo: name of repo in ~/repos/"
        echo "  name: name for the tree/branch"
        echo "  -r, --rev: revision to branch from (default: trunk())"
        echo "  example: tree-new myrepo feature -r 'main~3'"
        return 1
    fi

    local base_rev="${base_rev:-trunk()}"
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

    # Name the working-copy change and create a bookmark
    jj -R "$tree_path" describe -m "$name"
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

tree-find() {
    local repo=""
    local search=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                echo "Usage: tree-find <repo> <search-string>"
                echo "  repo: name of repo in ~/repos/"
                echo "  search: substring to match in commit descriptions"
                return 0
                ;;
            *)
                if [ -z "$repo" ]; then
                    repo="$1"
                elif [ -z "$search" ]; then
                    search="$1"
                else
                    echo "Unexpected argument: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [ -z "$repo" ] || [ -z "$search" ]; then
        echo "Usage: tree-find <repo> <search-string>"
        return 1
    fi

    local repo_path="$REPOS_DIR/$repo"
    if [ ! -d "$repo_path" ]; then
        echo "Repo not found: $repo_path"
        return 1
    fi

    # Get all workspaces (skip default)
    local workspaces=()
    while IFS= read -r line; do
        local ws_name="${line%%:*}"
        [ "$ws_name" = "default" ] && continue
        workspaces+=("$ws_name")
    done < <(jj -R "$repo_path" workspace list 2>/dev/null)

    if [ ${#workspaces[@]} -eq 0 ]; then
        echo "No workspaces found in $repo"
        return 1
    fi

    # For each workspace, check if any matching commit is in its stack
    local matching_trees=()
    local found
    for ws in "${workspaces[@]}"; do
        found=$(jj -R "$repo_path" log --no-graph --limit 1 \
            -r "description(substring:\"$search\") & ((trunk()..\"$ws\"@) | descendants(\"$ws\"@))" \
            -T 'change_id' 2>/dev/null)
        if [ -n "$found" ]; then
            matching_trees+=("$ws")
        fi
    done

    if [ ${#matching_trees[@]} -eq 0 ]; then
        echo "No workspace found containing commits matching: $search"
        return 1
    fi

    local target
    if [ ${#matching_trees[@]} -eq 1 ]; then
        target="${matching_trees[1]}"
    else
        target=$(printf '%s\n' "${matching_trees[@]}" | fzf --prompt="Select workspace: ")
        if [ -z "$target" ]; then
            return 1
        fi
    fi

    tree-open "$target"
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

    # Forget the workspace in jj
    echo "Forgetting workspace: $name"
    jj -R "$repo_path" workspace forget "$name"

    # Remove the directory
    echo "Removing directory: $tree_path"
    rm -rf "$tree_path"

    # Kill tmux session last — if we're running inside it, everything above
    # needs to finish before the session dies
    if tmux has-session -t "$name" 2>/dev/null; then
        echo "Killing tmux session: $name"
        tmux kill-session -t "$name"
    fi

    echo "Done."
}
