# Dotfiles git status notice (cached, refreshed at most once per hour).

dotfiles_status_notice() {
  command -v git >/dev/null 2>&1 || return 0

  local repo cache_root cache_dir cache_file lock_dir
  local now ts repo_status behind ahead max_age age

  repo="${DOTFILES_DIR:-$HOME/dotfiles}"
  [ -d "$repo" ] || return 0
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
  cache_dir="$cache_root/dotfiles"
  cache_file="$cache_dir/status"
  lock_dir="$cache_dir/.lock"

  now="$(date +%s)"
  ts=0
  repo_status=""
  behind=0
  ahead=0

  if [ -f "$cache_file" ]; then
    IFS='|' read -r ts repo_status behind ahead < "$cache_file"
    ts="${ts:-0}"
    repo_status="${repo_status:-}"
    behind="${behind:-0}"
    ahead="${ahead:-0}"
  fi

  max_age=3600
  age=$((now - ts))
  if [ "$ts" -le 0 ] || [ "$age" -ge "$max_age" ]; then
    (
      mkdir -p "$cache_dir" 2>/dev/null
      if mkdir "$lock_dir" 2>/dev/null; then
        trap 'rmdir "$lock_dir" 2>/dev/null' EXIT

        git -C "$repo" fetch --quiet --prune >/dev/null 2>&1 || exit 0

        local upstream counts b a st
        upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)" || {
          printf '%s|no-upstream|0|0\n' "$(date +%s)" > "$cache_file"
          exit 0
        }

        counts="$(git -C "$repo" rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null)" || exit 0
        set -- $counts
        b="${1:-0}"
        a="${2:-0}"

        if [ "$b" -gt 0 ] && [ "$a" -gt 0 ]; then
          st="diverged"
        elif [ "$b" -gt 0 ]; then
          st="behind"
        elif [ "$a" -gt 0 ]; then
          st="ahead"
        else
          st="clean"
        fi

        printf '%s|%s|%s|%s\n' "$(date +%s)" "$st" "$b" "$a" > "$cache_file"
      fi
    ) >/dev/null 2>&1 &!
  fi

  case "$repo_status" in
    behind)
      printf '[dotfiles] behind %s -> pull\n' "$behind"
      ;;
    ahead)
      printf '[dotfiles] ahead %s -> push\n' "$ahead"
      ;;
    diverged)
      printf '[dotfiles] diverged (behind %s / ahead %s)\n' "$behind" "$ahead"
      ;;
    no-upstream)
      printf '[dotfiles] no upstream set\n'
      ;;
  esac
}

dotfiles_status_notice
