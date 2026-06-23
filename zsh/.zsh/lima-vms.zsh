# Lima VM management functions
# Manages development VMs with tmux integration, mirroring the tree-* workflow
# tmux runs INSIDE the VM so new panes/windows are automatically in the VM

VM_TEMPLATE="$DOTFILES_DIR/lima/base.yaml"

vm-new() {
    local name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                echo "Usage: vm-new <name>"
                echo "  name: name for the VM"
                echo "  Creates an Ubuntu VM, provisions it with dotfiles, and attaches a tmux session."
                return 0
                ;;
            -*)
                echo "Unknown option: $1"
                return 1
                ;;
            *)
                if [ -z "$name" ]; then
                    name="$1"
                else
                    echo "Unexpected argument: $1"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [ -z "$name" ]; then
        echo "Usage: vm-new <name>"
        return 1
    fi

    if ! command -v limactl &>/dev/null; then
        echo "limactl not found. Install lima: brew install lima"
        return 1
    fi

    if limactl list -q 2>/dev/null | grep -qx "$name"; then
        echo "VM already exists: $name"
        return 1
    fi

    if [ ! -f "$VM_TEMPLATE" ]; then
        echo "Template not found: $VM_TEMPLATE"
        return 1
    fi

    echo "Creating VM: $name"
    limactl create --name "$name" "$VM_TEMPLATE"
    limactl start "$name"

    # Provision dotfiles
    # NOTE: ~ must be inside single-quoted bash -c to expand in the VM, not the host
    echo "Copying dotfiles..."
    limactl shell "$name" -- bash -c 'mkdir -p ~/dotfiles'
    # COPYFILE_DISABLE=1 suppresses macOS ._ resource fork files in tar
    (cd "$DOTFILES_DIR" && COPYFILE_DISABLE=1 tar cf - .) | limactl shell "$name" -- bash -c 'tar xf - -C ~/dotfiles'

    echo "Running install..."
    limactl shell "$name" -- bash -c 'cd ~/dotfiles && git submodule update --init --recursive && SHELL=/usr/bin/zsh ./install.sh'

    echo "VM ready: $name"

    # Start tmux inside the VM and attach (--shell forces zsh regardless of $SHELL)
    limactl shell --shell /usr/bin/zsh "$name" -- tmux new-session -s "$name"
}

vm-open() {
    local no_tmux=0
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-tmux) no_tmux=1; shift ;;
            *) args+=("$1"); shift ;;
        esac
    done

    if [ ${#args[@]} -eq 0 ]; then
        echo "Usage: vm-open [--no-tmux] <name>"
        echo "  name: VM name or partial match"
        vm-list
        return 1
    fi
    local name="${args[1]}"

    if ! command -v limactl &>/dev/null; then
        echo "limactl not found. Install lima: brew install lima"
        return 1
    fi

    # Check if VM exists (exact match)
    if ! limactl list -q 2>/dev/null | grep -qx "$name"; then
        # Try partial match
        local matches=(${(f)"$(limactl list -q 2>/dev/null | grep "$name")"})
        if [ ${#matches[@]} -eq 0 ]; then
            echo "No VM found matching: $name"
            vm-list
            return 1
        elif [ ${#matches[@]} -gt 1 ]; then
            # Use fzf if available
            if command -v fzf &>/dev/null; then
                name="$(printf '%s\n' "${matches[@]}" | fzf --prompt="Select VM: ")" || return 0
            else
                echo "Multiple matches:"
                printf '  %s\n' "${matches[@]}"
                return 1
            fi
        else
            name="${matches[1]}"
        fi
    fi

    # Start if stopped
    local vm_status
    vm_status="$(limactl list --json 2>/dev/null | jq -r "select(.name == \"$name\") | .status")"
    if [ "$vm_status" = "Stopped" ]; then
        echo "Starting VM: $name"
        limactl start "$name"
    fi

    if [ "$no_tmux" -eq 1 ]; then
        limactl shell --shell /usr/bin/zsh "$name"
        return
    fi

    # Attach to existing tmux session inside VM, or create a new one
    if limactl shell "$name" -- tmux has-session -t "$name" 2>/dev/null; then
        limactl shell --shell /usr/bin/zsh "$name" -- tmux attach -t "$name"
    else
        limactl shell --shell /usr/bin/zsh "$name" -- tmux new-session -s "$name"
    fi
}

vm-list() {
    if ! command -v limactl &>/dev/null; then
        echo "limactl not found. Install lima: brew install lima"
        return 1
    fi

    limactl list 2>/dev/null
}

vm-rm() {
    if [ -z "$1" ]; then
        echo "Usage: vm-rm <name>"
        return 1
    fi
    local name="$1"

    if ! command -v limactl &>/dev/null; then
        echo "limactl not found. Install lima: brew install lima"
        return 1
    fi

    if ! limactl list -q 2>/dev/null | grep -qx "$name"; then
        echo "VM not found: $name"
        return 1
    fi

    echo "Stopping VM: $name"
    limactl stop "$name" 2>/dev/null || true

    echo "Deleting VM: $name"
    limactl delete "$name"

    echo "Done."
}
