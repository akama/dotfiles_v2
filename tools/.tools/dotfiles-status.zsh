# Dotfiles git status notice (fetch at most once per hour).

dotfiles_status_notice() {
  command -v git >/dev/null 2>&1 || return 0

  local repo cache_root cache_dir cache_file lock_dir
  local now ts behind ahead max_age age
  local dirty upstream counts msg

  repo="${DOTFILES_DIR:-$HOME/dotfiles}"
  [ -d "$repo" ] || return 0
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
  cache_dir="$cache_root/dotfiles"
  cache_file="$cache_dir/last_fetch"
  lock_dir="$cache_dir/.lock"

  now="$(date +%s)"
  ts=0
  behind=0
  ahead=0

  if [ -f "$cache_file" ]; then
    read -r ts < "$cache_file"
    ts="${ts:-0}"
  fi

  case "$ts" in
    ''|*[!0-9]*) ts=0 ;;
  esac

  __dotfiles_status_fetch() {
    (
      mkdir -p "$cache_dir" 2>/dev/null
      if mkdir "$lock_dir" 2>/dev/null; then
        trap 'rmdir "$lock_dir" 2>/dev/null' EXIT

        if git -C "$repo" fetch --quiet --prune >/dev/null 2>&1; then
          printf '%s\n' "$(date +%s)" > "$cache_file"
        fi
      fi
    )
  }

  max_age=3600
  age=$((now - ts))
  if [ "$ts" -le 0 ] || [ "$age" -ge "$max_age" ]; then
    __dotfiles_status_fetch >/dev/null 2>&1 &!
  fi
  unset -f __dotfiles_status_fetch

  dirty=""
  if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
    dirty="dirty"
  fi

  msg=""
  __dotfiles_status_add() {
    if [ -n "$msg" ]; then
      msg="${msg}, $1"
    else
      msg="$1"
    fi
  }

  if [ -n "$dirty" ]; then
    __dotfiles_status_add "$dirty"
  fi

  upstream="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)" || upstream=""
  if [ -z "$upstream" ]; then
    __dotfiles_status_add "no upstream set"
  else
    counts="$(git -C "$repo" rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null)" || counts=""
    IFS=$' \t' read -r behind ahead <<< "$counts"
    behind="${behind:-0}"
    ahead="${ahead:-0}"

    if [ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ]; then
      __dotfiles_status_add "diverged $behind/$ahead"
    elif [ "$behind" -gt 0 ]; then
      __dotfiles_status_add "behind $behind"
    elif [ "$ahead" -gt 0 ]; then
      __dotfiles_status_add "ahead $ahead"
    fi
  fi

  unset -f __dotfiles_status_add

  if [ -n "$msg" ]; then
    printf 'dotfiles - %s\n' "$msg"
  fi
}

dotfiles_status_notice
