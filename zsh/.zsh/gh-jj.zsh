# gh-jj: helper to run gh CLI in both git and jj repos
# Unsets GITHUB_TOKEN (use keyring auth) and resolves repo from jj when not in git.

# Resolve GitHub owner/repo from git or jj
_gh_repo() {
    if git rev-parse --git-dir &>/dev/null; then
        command env -u GITHUB_TOKEN gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null
    else
        local url
        url="$(jj git remote list 2>/dev/null | awk '$1 == "origin" { print $2 }')"
        [[ -z "$url" ]] && return 1
        url="${url%.git}"
        url="${url##*github.com[:/]}"
        printf '%s' "$url"
    fi
}

# Run gh, adding -R for repo-scoped commands when in a jj workspace
_gh() {
    if git rev-parse --git-dir &>/dev/null; then
        command env -u GITHUB_TOKEN gh "$@"
        return
    fi

    # Only repo-scoped subcommands need -R
    case "$1" in
        pr|issue|release|repo)
            local repo
            repo="$(_gh_repo)"
            if [[ -n "$repo" ]]; then
                command env -u GITHUB_TOKEN gh "$@" -R "$repo"
            else
                command env -u GITHUB_TOKEN gh "$@"
            fi
            ;;
        *)
            command env -u GITHUB_TOKEN gh "$@"
            ;;
    esac
}
