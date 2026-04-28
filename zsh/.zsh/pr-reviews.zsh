# pr-reviews: show reviews and comments for a specific PR

pr-reviews() {
    if [[ "$1" == "-h" || "$1" == "--help" || -z "$1" ]]; then
        echo "Usage: pr-reviews <number>"
        echo "  Shows reviews, inline review threads, and conversation comments for a PR."
        echo "  Resolved threads are hidden by default. Use -a to show all."
        return 0
    fi

    if ! command -v gh >/dev/null 2>&1; then
        echo "pr-reviews: gh (GitHub CLI) is required" >&2
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "pr-reviews: jq is required" >&2
        return 1
    fi

    local show_all=0
    if [[ "$1" == "-a" || "$1" == "--all" ]]; then
        show_all=1
        shift
    fi
    # Support: pr-reviews 123 -a
    if [[ "$2" == "-a" || "$2" == "--all" ]]; then
        show_all=1
    fi

    local pr_number="${1#\#}"

    # Fetch PR metadata, reviews, and comments in one call
    local json
    json="$(_gh pr view "$pr_number" --json title,state,author,reviews,comments,reviewRequests 2>&1)" || {
        echo "pr-reviews: failed to fetch PR #${pr_number}: $json" >&2
        return 1
    }

    local title state pr_author
    title="$(printf '%s' "$json" | jq -r '.title')"
    state="$(printf '%s' "$json" | jq -r '.state')"
    pr_author="$(printf '%s' "$json" | jq -r '.author.login')"

    local reset="\033[0m"
    local bold="\033[1m"
    local dim="\033[90m"
    local green="\033[32m"
    local red="\033[31m"
    local yellow="\033[33m"
    local blue="\033[34m"

    printf "${bold}#%s${reset} %s ${dim}(%s by %s)${reset}\n\n" "$pr_number" "$title" "$state" "$pr_author"

    # Helper: ISO date -> relative age string (e.g. "3d", "2w", "1mo")
    _pr_reviews_age() {
        local iso_date="$1"
        local short_date="${iso_date%%T*}"
        local then_ts now_ts days
        then_ts="$(date -j -f "%Y-%m-%d" "$short_date" +%s 2>/dev/null)" || { printf "%s" "$short_date"; return; }
        now_ts="$(date +%s)"
        days=$(( (now_ts - then_ts) / 86400 ))
        if (( days == 0 )); then
            printf "today"
        elif (( days == 1 )); then
            printf "1d"
        elif (( days < 7 )); then
            printf "%dd" "$days"
        elif (( days < 30 )); then
            printf "%dw" $(( days / 7 ))
        elif (( days < 365 )); then
            printf "%dmo" $(( days / 30 ))
        else
            printf "%dy" $(( days / 365 ))
        fi
    }

    # Helper: decode base64 body, print up to max_lines with given indent
    _pr_reviews_body() {
        local encoded="$1" max_lines="${2:-3}" indent="${3:-    }"
        if [[ -z "$encoded" || "$encoded" == "IA==" || "$encoded" == "Cg==" ]]; then
            return
        fi
        local decoded
        decoded="$(printf '%s' "$encoded" | base64 -d 2>/dev/null)"
        if [[ -n "$decoded" ]]; then
            printf '%s\n' "$decoded" | head -"$max_lines" | while IFS= read -r line; do
                printf "%s%s\n" "$indent" "$line"
            done
        fi
    }

    # Pre-declare loop variables to avoid 'local' inside piped while loops
    # (zsh leaks local declarations to stdout in pipe subshells)
    local _age _color _icon _short_date _markers _connector

    # Reviews — latest meaningful state per author
    local review_output
    review_output="$(printf '%s' "$json" | jq -r '
        [.reviews[] | {
            author: .author.login,
            state: .state,
            body: (.body | @base64),
            submittedAt: .submittedAt
        }]
        | group_by(.author)
        | map(
            sort_by(.submittedAt)
            | ([ .[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED") ] | last)
              // last
        )
        | map(select(. != null))
        | sort_by(.submittedAt)[]
        | "\(.submittedAt)\t\(.author)\t\(.state)\t\(.body)"
    ')"

    if [[ -n "$review_output" ]]; then
        printf "${bold}Reviews${reset}\n"
        echo "$review_output" | while IFS=$'\t' read -r ts author review_state body; do
            _color="" _icon=""
            case "$review_state" in
                APPROVED)          _color="$green"; _icon="✓" ;;
                CHANGES_REQUESTED) _color="$yellow"; _icon="✗" ;;
                COMMENTED)         _color="$blue"; _icon="●" ;;
                DISMISSED)         _color="$dim"; _icon="○" ;;
                *)                 _color="$dim"; _icon="?" ;;
            esac
            _age="$(_pr_reviews_age "$ts")"
            printf "  ${_color}%s %-20s${reset} ${dim}%s${reset} %s\n" "$_icon" "$review_state" "$_age" "$author"
            _pr_reviews_body "$body" 3
        done
        echo ""
    fi

    # Conversation comments — base64 body
    local comment_count
    comment_count="$(printf '%s' "$json" | jq '[.comments[]] | length')"

    if (( comment_count > 0 )); then
        printf "${bold}Comments${reset} ${dim}(%d)${reset}\n" "$comment_count"
        printf '%s' "$json" | jq -r '
            [.comments[] | {
                author: .author.login,
                body: (.body | @base64),
                createdAt: .createdAt
            }] | sort_by(.createdAt)[] |
            "\(.createdAt)\t\(.author)\t\(.body)"
        ' | while IFS=$'\t' read -r ts author body; do
            _age="$(_pr_reviews_age "$ts")"
            printf "  ${dim}%s${reset} ${blue}%s${reset}\n" "$_age" "$author"
            _pr_reviews_body "$body" 3
        done
        echo ""
    fi

    # Inline review threads via GraphQL (gives us isResolved)
    local repo owner repo_name
    repo="$(_gh_repo)"
    if [[ -n "$repo" ]]; then
        owner="${repo%%/*}"
        repo_name="${repo#*/}"

        local gql_query
        gql_query='query($owner: String!, $repo: String!, $pr: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $pr) {
              reviewThreads(first: 100) {
                nodes {
                  isResolved
                  isOutdated
                  path
                  line
                  comments(first: 10) {
                    nodes {
                      author { login }
                      body
                      createdAt
                    }
                  }
                }
              }
            }
          }
        }'

        local threads_json
        threads_json="$(command env -u GITHUB_TOKEN gh api graphql \
            -F owner="$owner" \
            -F repo="$repo_name" \
            -F "pr=$pr_number" \
            -f query="$gql_query" 2>/dev/null)"

        if [[ -n "$threads_json" ]]; then
            local total_threads resolved_threads unresolved_threads
            total_threads="$(printf '%s' "$threads_json" | jq '[.data.repository.pullRequest.reviewThreads.nodes[]] | length')"
            resolved_threads="$(printf '%s' "$threads_json" | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved)] | length')"
            unresolved_threads=$(( total_threads - resolved_threads ))

            if (( total_threads > 0 )); then
                local resolved_label
                if (( show_all )); then
                    resolved_label=" ${dim}(${resolved_threads} resolved, showing all)${reset}"
                else
                    resolved_label=""
                    if (( resolved_threads > 0 )); then
                        resolved_label=" ${dim}(${resolved_threads} resolved, hidden)${reset}"
                    fi
                fi

                local display_count
                if (( show_all )); then
                    display_count=$total_threads
                else
                    display_count=$unresolved_threads
                fi

                if (( display_count > 0 )); then
                    printf "${bold}Inline threads${reset} ${dim}(%d)${reset}%b\n" "$display_count" "$resolved_label"
                    # Emit H (header) and R (reply) lines per thread, with E (end) markers
                    printf '%s' "$threads_json" | jq -r --arg filter "$show_all" '
                        [.data.repository.pullRequest.reviewThreads.nodes[]
                         | (if $filter == "1" then . else select(.isResolved | not) end)
                        ]
                        | sort_by(.comments.nodes[0].createdAt)[]
                        | . as $thread
                        | (.comments.nodes | length) as $total
                        | .comments.nodes
                        | to_entries[]
                        | if .key == 0 then
                            "H\t\(.value.createdAt)\t\(.value.author.login)\t\($thread.path):\($thread.line // "")\t\(.value.body | @base64)\t\($thread.isResolved)\t\($thread.isOutdated)"
                          elif .key == ($total - 1) then
                            "E\t\(.value.createdAt)\t\(.value.author.login)\t\(.value.body | @base64)"
                          else
                            "R\t\(.value.createdAt)\t\(.value.author.login)\t\(.value.body | @base64)"
                          end
                    ' | while IFS=$'\t' read -r kind ts author loc_or_body rest1 rest2 rest3; do
                        _age="$(_pr_reviews_age "$ts")"
                        if [[ "$kind" == "H" ]]; then
                            _markers=""
                            if [[ "$rest2" == "true" ]]; then
                                _markers="${_markers} ${green}✓resolved${reset}"
                            fi
                            if [[ "$rest3" == "true" ]]; then
                                _markers="${_markers} ${dim}(outdated)${reset}"
                            fi
                            printf "\n  ${dim}%-5s${reset} ${blue}%s${reset} ${dim}@ %s${reset}%b\n" "$_age" "$author" "$loc_or_body" "$_markers"
                            _pr_reviews_body "$rest1" 2 "        "
                        else
                            _connector="├─"
                            [[ "$kind" == "E" ]] && _connector="└─"
                            printf "        ${dim}%s${reset} ${dim}%-5s${reset} ${blue}%s${reset}\n" "$_connector" "$_age" "$author"
                            if [[ "$kind" == "E" ]]; then
                                _pr_reviews_body "$loc_or_body" 2 "           "
                            else
                                _pr_reviews_body "$loc_or_body" 2 "        │  "
                            fi
                        fi
                    done
                    echo ""
                elif (( resolved_threads > 0 )); then
                    printf "${bold}Inline threads${reset} ${dim}(%d resolved, use -a to show)${reset}\n" "$resolved_threads"
                fi
            fi
        fi
    fi

    local review_has_output=0
    [[ -n "$review_output" ]] && review_has_output=1
    if (( review_has_output == 0 && comment_count == 0 )); then
        echo "  No reviews or comments yet."
    fi
}
