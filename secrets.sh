#!/bin/bash

set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
SKIP_DIRS=".git"
CACHE_DIR="$HOME/.cache/dotfiles/secrets"

AGE_SSH_KEY="${AGE_SSH_KEY:-$HOME/.ssh/id_ed25519}"
AGE_RECIPIENTS="${AGE_RECIPIENTS:-$DOTFILES_DIR/.age-recipients}"

# --- Shared helpers ---

hash_content() {
    sha256sum | cut -d' ' -f1
}

get_stored_hash() {
    local hash_file="$1"
    if [[ -f "$hash_file" ]]; then
        cat "$hash_file"
    fi
}

store_hash() {
    local hash_file="$1"
    local hash="$2"
    mkdir -p "$(dirname "$hash_file")"
    printf '%s' "$hash" > "$hash_file"
}

hash_file_path() {
    # age_rel_path is relative to DOTFILES_DIR, e.g. zsh/.env_secrets.age
    local age_rel_path="$1"
    local plain="${age_rel_path%.age}"
    echo "$CACHE_DIR/${plain}.sha256"
}

decrypt_age_to_stdout() {
    local age_file="$1"
    age -d -i "$AGE_SSH_KEY" "$age_file" 2>/dev/null
}

encrypt_to_age() {
    local plaintext_file="$1"
    local age_file="$2"
    if [[ ! -f "$AGE_RECIPIENTS" ]]; then
        echo "Error: recipients file not found at $AGE_RECIPIENTS" >&2
        echo "Create it with: ssh-keygen -y -f ~/.ssh/id_ed25519 >> $AGE_RECIPIENTS" >&2
        return 1
    fi
    mkdir -p "$(dirname "$age_file")"
    age -e -R "$AGE_RECIPIENTS" -o "$age_file" < "$plaintext_file"
}

# sync_secret <age_file_abs> <target_abs> <age_rel_path>
# Implements three-way sync logic.
# Returns 0 on success, 1 on conflict/skip.
sync_secret() {
    local age_file="$1"
    local target="$2"
    local age_rel_path="$3"
    local hash_file
    hash_file="$(hash_file_path "$age_rel_path")"

    # Decrypt repo version to temp file
    local tmp
    tmp="$(mktemp)"
    trap "rm -f '$tmp'" RETURN

    if ! decrypt_age_to_stdout "$age_file" > "$tmp"; then
        echo "  Error: failed to decrypt $age_file" >&2
        return 1
    fi

    local repo_hash local_hash base_hash
    repo_hash="$(hash_content < "$tmp")"
    base_hash="$(get_stored_hash "$hash_file")"

    if [[ -f "$target" ]]; then
        local_hash="$(hash_content < "$target")"
    else
        local_hash=""
    fi

    # First run / no local file
    if [[ -z "$local_hash" && -z "$base_hash" ]]; then
        echo "  Decrypting: $age_file -> $target (first run)"
        mkdir -p "$(dirname "$target")"
        cp "$tmp" "$target"
        chmod 600 "$target"
        store_hash "$hash_file" "$repo_hash"
        return 0
    fi

    # No local file but we had a previous sync — treat as local deleted, repo wins
    if [[ -z "$local_hash" ]]; then
        echo "  Decrypting: $age_file -> $target (local missing)"
        mkdir -p "$(dirname "$target")"
        cp "$tmp" "$target"
        chmod 600 "$target"
        store_hash "$hash_file" "$repo_hash"
        return 0
    fi

    local repo_changed=false
    local local_changed=false

    if [[ "$repo_hash" != "$base_hash" ]]; then
        repo_changed=true
    fi
    if [[ "$local_hash" != "$base_hash" ]]; then
        local_changed=true
    fi

    if [[ "$repo_changed" == false && "$local_changed" == false ]]; then
        echo "  In sync: $target"
        return 0
    fi

    if [[ "$repo_changed" == false && "$local_changed" == true ]]; then
        echo "  Local modified: re-encrypting $target -> $age_file"
        encrypt_to_age "$target" "$age_file"
        store_hash "$hash_file" "$local_hash"
        return 0
    fi

    if [[ "$repo_changed" == true && "$local_changed" == false ]]; then
        echo "  Repo updated: decrypting $age_file -> $target"
        cp "$tmp" "$target"
        chmod 600 "$target"
        store_hash "$hash_file" "$repo_hash"
        return 0
    fi

    # Both changed — conflict
    if [[ "$repo_hash" == "$local_hash" ]]; then
        # Same content, no real conflict
        echo "  In sync (converged): $target"
        store_hash "$hash_file" "$repo_hash"
        return 0
    fi

    echo "  CONFLICT: $target"
    echo "    Both repo and local have changed since last sync."
    echo "    --- Repo vs Local diff ---"
    diff -u --label "repo: $age_rel_path" "$tmp" --label "local: $target" "$target" || true
    echo ""
    echo "    Skipping this file. Resolve manually:"
    echo "      To keep local:  ./secrets.sh encrypt $target $age_rel_path"
    echo "      To keep repo:   age -d -i $AGE_SSH_KEY $age_file > $target"
    echo "    Then run install again."
    return 1
}

# --- Walk all .age files ---

find_age_files() {
    for dir in "$DOTFILES_DIR"/*/; do
        local dirname
        dirname="$(basename "$dir")"
        [[ " $SKIP_DIRS " =~ " $dirname " ]] && continue

        while IFS= read -r -d '' age_file; do
            local rel_path="${age_file#$DOTFILES_DIR/}"
            local plain_name
            plain_name="$(basename "${age_file%.age}")"
            local target="$HOME/$plain_name"
            echo "$age_file"$'\t'"$target"$'\t'"$rel_path"
        done < <(find "$dir" -name '*.age' -print0 2>/dev/null)
    done
}

# --- Subcommands ---

cmd_decrypt() {
    echo "Syncing secrets..."
    local had_conflict=false
    while IFS=$'\t' read -r age_file target rel_path; do
        if ! sync_secret "$age_file" "$target" "$rel_path"; then
            had_conflict=true
        fi
    done < <(find_age_files)
    if [[ "$had_conflict" == true ]]; then
        echo ""
        echo "Some secrets had conflicts. See above for details."
        return 1
    fi
    echo "Secrets sync complete."
}

cmd_diff() {
    echo "Checking secrets status..."
    local found=false
    while IFS=$'\t' read -r age_file target rel_path; do
        found=true
        local hash_file
        hash_file="$(hash_file_path "$rel_path")"

        local tmp
        tmp="$(mktemp)"

        if ! decrypt_age_to_stdout "$age_file" > "$tmp"; then
            echo "  Error: failed to decrypt $age_file" >&2
            rm -f "$tmp"
            continue
        fi

        local repo_hash local_hash base_hash
        repo_hash="$(hash_content < "$tmp")"
        base_hash="$(get_stored_hash "$hash_file")"

        if [[ -f "$target" ]]; then
            local_hash="$(hash_content < "$target")"
        else
            echo "  $rel_path: local file missing ($target)"
            rm -f "$tmp"
            continue
        fi

        local repo_changed=false local_changed=false
        [[ "$repo_hash" != "$base_hash" ]] && repo_changed=true
        [[ "$local_hash" != "$base_hash" ]] && local_changed=true

        if [[ "$repo_changed" == false && "$local_changed" == false ]]; then
            echo "  $rel_path: in sync"
        elif [[ "$repo_changed" == false && "$local_changed" == true ]]; then
            echo "  $rel_path: local modified"
            diff -u --label "repo: $rel_path" "$tmp" --label "local: $target" "$target" || true
        elif [[ "$repo_changed" == true && "$local_changed" == false ]]; then
            echo "  $rel_path: repo updated"
            diff -u --label "local: $target" "$target" --label "repo: $rel_path" "$tmp" || true
        else
            if [[ "$repo_hash" == "$local_hash" ]]; then
                echo "  $rel_path: in sync (converged)"
            else
                echo "  $rel_path: CONFLICT (both changed)"
                echo "    --- Repo version vs Local ---"
                diff -u --label "repo: $rel_path" "$tmp" --label "local: $target" "$target" || true
            fi
        fi

        rm -f "$tmp"
    done < <(find_age_files)

    if [[ "$found" == false ]]; then
        echo "  No .age files found."
    fi
}

reencrypt_all() {
    local count=0
    while IFS=$'\t' read -r age_file target rel_path; do
        local tmp
        tmp="$(mktemp)"
        if ! decrypt_age_to_stdout "$age_file" > "$tmp"; then
            echo "  Error: failed to decrypt $age_file (skipping)" >&2
            rm -f "$tmp"
            continue
        fi
        encrypt_to_age "$tmp" "$age_file"
        rm -f "$tmp"
        echo "  Re-encrypted: $rel_path"
        count=$((count + 1))
    done < <(find_age_files)
    echo "Re-encrypted $count file(s)."
}

cmd_add_key() {
    local key_input="$1"

    # Default to local machine's public key
    if [[ -z "$key_input" ]]; then
        local pub="${AGE_SSH_KEY}.pub"
        if [[ ! -f "$pub" ]]; then
            echo "Error: no key specified and $pub not found" >&2
            return 1
        fi
        key_input="$pub"
    fi

    # Read the key — from file or treat as literal key string
    local key_line
    if [[ -f "$key_input" ]]; then
        key_line="$(cat "$key_input")"
        echo "Adding key from: $key_input"
    else
        key_line="$key_input"
        echo "Adding key: ${key_line:0:40}..."
    fi

    # Create recipients file if it doesn't exist
    touch "$AGE_RECIPIENTS"

    # Check for duplicates
    if grep -qFx "$key_line" "$AGE_RECIPIENTS"; then
        echo "Key already in $AGE_RECIPIENTS"
        return 0
    fi

    echo "$key_line" >> "$AGE_RECIPIENTS"
    echo "Added to $AGE_RECIPIENTS"

    # Re-encrypt all existing .age files with updated recipients
    local age_count
    age_count="$(find_age_files | wc -l)"
    if [[ "$age_count" -gt 0 ]]; then
        echo "Re-encrypting existing secrets with updated recipients..."
        reencrypt_all
    fi

    echo "Done. Remember to commit .age-recipients and any updated .age files."
}

cmd_remove_key() {
    local pattern="$1"

    if [[ -z "$pattern" ]]; then
        echo "Usage: secrets.sh remove-key <pattern>" >&2
        echo "  Pattern matches against lines in .age-recipients." >&2
        echo "  Use a unique substring of the key (e.g. hostname or key fingerprint)." >&2
        return 1
    fi

    if [[ ! -f "$AGE_RECIPIENTS" ]]; then
        echo "Error: $AGE_RECIPIENTS not found" >&2
        return 1
    fi

    # Show matching lines
    local matches
    matches="$(grep -F "$pattern" "$AGE_RECIPIENTS" || true)"
    if [[ -z "$matches" ]]; then
        echo "No keys matching '$pattern' found in $AGE_RECIPIENTS"
        return 1
    fi

    local match_count
    match_count="$(echo "$matches" | wc -l)"
    echo "Found $match_count matching key(s):"
    echo "$matches" | while IFS= read -r line; do
        echo "  ${line:0:60}..."
    done

    if [[ "$match_count" -gt 1 ]]; then
        echo "Error: pattern matches multiple keys. Use a more specific pattern." >&2
        return 1
    fi

    # Remove the matching line
    grep -vF "$pattern" "$AGE_RECIPIENTS" > "$AGE_RECIPIENTS.tmp"
    mv "$AGE_RECIPIENTS.tmp" "$AGE_RECIPIENTS"
    echo "Removed from $AGE_RECIPIENTS"

    # Check we still have recipients
    if [[ ! -s "$AGE_RECIPIENTS" ]]; then
        echo "Warning: .age-recipients is now empty. Cannot re-encrypt." >&2
        return 0
    fi

    # Re-encrypt all existing .age files
    local age_count
    age_count="$(find_age_files | wc -l)"
    if [[ "$age_count" -gt 0 ]]; then
        echo "Re-encrypting existing secrets with updated recipients..."
        reencrypt_all
    fi

    echo "Done. Remember to commit .age-recipients and any updated .age files."
}

cmd_encrypt() {
    local source_file="$1"
    local age_rel_path="$2"

    if [[ -z "$source_file" || -z "$age_rel_path" ]]; then
        echo "Usage: secrets.sh encrypt <local-file> <age-path>" >&2
        echo "Example: ./secrets.sh encrypt ~/.env_secrets zsh/.env_secrets.age" >&2
        return 1
    fi

    # Expand ~ in source_file
    source_file="${source_file/#\~/$HOME}"

    if [[ ! -f "$source_file" ]]; then
        echo "Error: source file not found: $source_file" >&2
        return 1
    fi

    # Ensure .age suffix
    if [[ "$age_rel_path" != *.age ]]; then
        age_rel_path="${age_rel_path}.age"
    fi

    local age_file="$DOTFILES_DIR/$age_rel_path"
    local hash_file
    hash_file="$(hash_file_path "$age_rel_path")"

    echo "Encrypting: $source_file -> $age_file"
    encrypt_to_age "$source_file" "$age_file"

    local content_hash
    content_hash="$(hash_content < "$source_file")"
    store_hash "$hash_file" "$content_hash"

    echo "Hash stored at: $hash_file"
    echo "Done. Remember to commit $age_rel_path"
}

# --- Main ---

# When sourced with --source-only, export helpers without running subcommands
[[ "${1:-}" == "--source-only" ]] && return 0 2>/dev/null || true

case "${1:-decrypt}" in
    decrypt)
        cmd_decrypt
        ;;
    diff)
        cmd_diff
        ;;
    encrypt)
        cmd_encrypt "$2" "$3"
        ;;
    add-key)
        cmd_add_key "$2"
        ;;
    remove-key)
        cmd_remove_key "$2"
        ;;
    --source-only)
        # Already handled above; this catches direct execution with --source-only
        ;;
    *)
        echo "Usage: secrets.sh <command>" >&2
        echo "" >&2
        echo "  decrypt              Sync all .age files (default)" >&2
        echo "  diff                 Show diffs between repo and local secrets" >&2
        echo "  encrypt <f> <path>   Encrypt local file to .age path in repo" >&2
        echo "  add-key [key|file]   Add SSH public key to recipients (default: local key)" >&2
        echo "  remove-key <pattern> Remove matching key from recipients" >&2
        exit 1
        ;;
esac
