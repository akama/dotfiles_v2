# pr-status: dashboard for open PRs with state classification and stack detection

pr-status() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: pr-status"
        echo "  Shows open PRs authored by you with review/CI state and stack structure."
        echo ""
        echo "States (first match wins):"
        echo "  draft             PR is in draft mode"
        echo "  ci-failing        A CI check failed"
        echo "  ci-pending        CI still running, none failed"
        echo "  changes-requested A human reviewer requested changes"
        echo "  ready-to-merge    Human approved, CI green, not draft"
        echo "  waiting-for-review Reviewers assigned, awaiting review"
        echo "  needs-reviewer    No reviewers assigned"
        echo ""
        echo "Environment:"
        echo "  PR_STATUS_AUTHOR  Override GitHub username (default: gh api user)"
        return 0
    fi

    if ! command -v gh >/dev/null 2>&1; then
        echo "pr-status: gh (GitHub CLI) is required" >&2
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "pr-status: jq is required" >&2
        return 1
    fi

    local author="${PR_STATUS_AUTHOR:-}"
    if [[ -z "$author" ]]; then
        author="$(command env -u GITHUB_TOKEN gh api user --jq .login 2>/dev/null)"
        if [[ -z "$author" ]]; then
            echo "pr-status: could not determine GitHub username" >&2
            return 1
        fi
    fi

    local json err
    json="$(command env -u GITHUB_TOKEN gh pr list -A "$author" --json number,title,headRefName,baseRefName,isDraft,reviewRequests,latestReviews,statusCheckRollup,state --limit 50 2>&1)" || {
        echo "pr-status: gh pr list failed: $json" >&2
        return 1
    }
    if [[ -z "$json" || "$json" == "[]" ]]; then
        echo "No open PRs found for $author"
        return 0
    fi

    local jq_script
    # Note: avoid != in jq script — zsh BANG_HIST mangles ! inside strings
    jq_script=$(cat <<'JQEOF'
def classify:
    if .isDraft then "draft"
    elif (.statusCheckRollup // [] | any(
        (.conclusion // "" | ascii_downcase) == "failure"
        or (.state // "" | ascii_downcase) == "failure"
        or (.state // "" | ascii_downcase) == "error"
    )) then "ci-failing"
    elif (.statusCheckRollup // [] | any(
        (.__typename == "CheckRun" and ((.status // "" | ascii_downcase) == "completed" | not))
        or (.__typename == "StatusContext" and (.state // "" | ascii_downcase) == "pending")
    )) then "ci-pending"
    elif ([(.latestReviews // [])[] | select(.authorAssociation == "NONE" | not)] | any(.state == "CHANGES_REQUESTED")) then "changes-requested"
    elif (
        (.isDraft | not)
        and ([(.latestReviews // [])[] | select(.authorAssociation == "NONE" | not)] | any(.state == "APPROVED"))
        and ((.statusCheckRollup // [] | length) > 0)
        and (.statusCheckRollup | all(
            ((.conclusion // "" | ascii_downcase) == "success" or (.conclusion // "" | ascii_downcase) == "neutral" or (.conclusion // "" | ascii_downcase) == "skipped")
            or ((.state // "" | ascii_downcase) == "success")
        ))
    ) then "ready-to-merge"
    elif ((.reviewRequests // []) | length) > 0 then "waiting-for-review"
    else "needs-reviewer"
    end;

(reduce .[] as $pr ({}; . + {($pr.headRefName): $pr.number})) as $head_map |

[.[] | {
    number,
    title,
    isDraft,
    headRefName,
    baseRefName,
    state: classify,
    parent: ($head_map[.baseRefName] // null)
}] |

. as $prs |

def children($num):
    [$prs[] | select(.parent == $num)] | sort_by(.number);

def render($depth):
    . as $pr |
    "\($depth)|\($pr.number)|\($pr.state)|\($pr.isDraft)|\($pr.title)",
    (children($pr.number)[] | render($depth + 1));

[.[] | select(.parent == null)] | sort_by(.number) | .[] | render(0)
JQEOF
)

    local lines
    lines="$(printf '%s\n' "$json" | jq -r "$jq_script" 2>/dev/null)"
    if [[ -z "$lines" ]]; then
        echo "No open PRs found for $author"
        return 0
    fi

    # Collect all lines into an array for sibling counting
    local -a all_lines
    while IFS= read -r line; do
        all_lines+=("$line")
    done <<< "$lines"

    local total=${#all_lines[@]}
    local i=1
    local depth number state is_draft title color prefix draft_marker
    local is_last j next next_depth indent d
    for line in "${all_lines[@]}"; do
        depth="${line%%|*}"; line="${line#*|}"
        number="${line%%|*}"; line="${line#*|}"
        state="${line%%|*}"; line="${line#*|}"
        is_draft="${line%%|*}"; line="${line#*|}"
        title="$line"

        # Determine color
        color=""
        case "$state" in
            ready-to-merge)     color="\033[32m" ;;  # green
            ci-failing)         color="\033[31m" ;;  # red
            changes-requested)  color="\033[33m" ;;  # yellow
            ci-pending)         color="\033[33m" ;;  # yellow
            waiting-for-review) color="\033[34m" ;;  # blue
            needs-reviewer)     color="\033[35m" ;;  # magenta
            draft)              color="\033[90m" ;;  # dim
        esac
        local reset="\033[0m"

        # Draft marker
        draft_marker=""
        if [[ "$is_draft" == "true" ]]; then
            draft_marker=" \033[90m[draft]${reset}"
        fi

        # Build prefix based on depth
        prefix=""
        if (( depth == 0 )); then
            prefix="● "
        else
            is_last=1
            j=$((i + 1))
            while (( j <= total )); do
                next="${all_lines[$j]}"
                next_depth="${next%%|*}"
                if (( next_depth < depth )); then
                    break
                elif (( next_depth == depth )); then
                    is_last=0
                    break
                fi
                j=$((j + 1))
            done

            indent=""
            d=1
            while (( d < depth )); do
                indent="${indent}│ "
                d=$((d + 1))
            done

            if (( is_last )); then
                prefix="${indent}└─● "
            else
                prefix="${indent}├─● "
            fi
        fi

        printf "${prefix}${color}#%-6s %-20s${reset}%s${draft_marker}\n" "$number" "$state" "$title"
        i=$((i + 1))
    done
}
