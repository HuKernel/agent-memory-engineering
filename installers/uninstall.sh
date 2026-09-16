#!/bin/sh
# Remove agent-memory-engineering from a host skills directory.
# Only removes directories that actually contain our SKILL.md (safety check).

set -eu

TARGET="all"
SCOPE="user"

usage() {
  cat <<'EOF'
Usage: ./installers/uninstall.sh [--target claude|codex|all] [--scope user|project]
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --scope)  SCOPE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$TARGET" in claude|codex|all) ;; *) echo "Invalid --target" >&2; exit 2 ;; esac
case "$SCOPE" in user|project) ;; *) echo "Invalid --scope" >&2; exit 2 ;; esac

SKILL_NAME=agent-memory-engineering

dest_dir_for() {
  case "$1:$SCOPE" in
    claude:user)    echo "$HOME/.claude/skills" ;;
    claude:project) echo "$PWD/.claude/skills" ;;
    codex:user)     echo "$HOME/.agents/skills" ;;
    codex:project)  echo "$PWD/.agents/skills" ;;
  esac
}

uninstall_one() {
  host="$1"
  dest="$(dest_dir_for "$host")/$SKILL_NAME"
  if [ -L "$dest" ]; then
    rm "$dest"
    echo "[$host] removed link: $dest"
    return 0
  fi
  if [ -d "$dest" ]; then
    if [ ! -f "$dest/SKILL.md" ]; then
      echo "[$host] ERROR: $dest has no SKILL.md - not removed (refusing to delete unknown directory)" >&2
      exit 1
    fi
    rm -rf "$dest"
    echo "[$host] removed: $dest"
    return 0
  fi
  echo "[$host] not installed at: $dest (nothing to do)"
}

[ "$TARGET" = "claude" ] || [ "$TARGET" = "all" ] && uninstall_one claude
[ "$TARGET" = "codex" ]  || [ "$TARGET" = "all" ] && uninstall_one codex
echo "Done."
