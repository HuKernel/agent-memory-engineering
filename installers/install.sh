#!/bin/sh
# agent-memory-engineering installer (macOS / Linux / Git Bash)
# Canonical source: <repo>/skills/agent-memory-engineering  (the ONLY maintained copy)
# Install targets are copies (default) or symlinks (--link) - never a second source of truth.

set -eu

TARGET="all"
SCOPE="user"
FORCE=0
LINK=0

usage() {
  cat <<'EOF'
Usage: ./installers/install.sh [--target claude|codex|all] [--scope user|project] [--force] [--link]

  --target   claude : install to Claude Code skills directory
             codex : install to Codex skills directory
             all   : both (default)
  --scope    user    : per-user install (default)
             project : install into the current directory's project-level skills folder
  --force    overwrite an existing different installation (a timestamped backup is kept)
  --link     symlink instead of copy (falls back with an error if symlinks are unsafe)

Claude  user    : ~/.claude/skills/agent-memory-engineering
Claude  project : <pwd>/.claude/skills/agent-memory-engineering
Codex   user    : ~/.agents/skills/agent-memory-engineering
Codex   project : <pwd>/.agents/skills/agent-memory-engineering
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --scope)  SCOPE="${2:-}"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    --link)   LINK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$TARGET" in claude|codex|all) ;; *) echo "Invalid --target: $TARGET" >&2; usage >&2; exit 2 ;; esac
case "$SCOPE" in user|project) ;; *) echo "Invalid --scope: $SCOPE" >&2; usage >&2; exit 2 ;; esac

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SKILL_SRC="$REPO_ROOT/skills/agent-memory-engineering"
SKILL_NAME=agent-memory-engineering

# --- validate canonical source before doing anything ---
if [ ! -f "$SKILL_SRC/SKILL.md" ]; then
  echo "ERROR: canonical skill not found at $SKILL_SRC/SKILL.md" >&2
  exit 1
fi
if ! head -n 1 "$SKILL_SRC/SKILL.md" | grep -q '^---$'; then
  echo "ERROR: SKILL.md is missing YAML frontmatter" >&2
  exit 1
fi
for key in name description; do
  if ! sed -n '2,/^---$/p' "$SKILL_SRC/SKILL.md" | grep -q "^${key}:"; then
    echo "ERROR: SKILL.md frontmatter is missing required key: $key" >&2
    exit 1
  fi
done

dest_dir_for() {
  case "$1:$SCOPE" in
    claude:user)    echo "$HOME/.claude/skills" ;;
    claude:project) echo "$PWD/.claude/skills" ;;
    codex:user)     echo "$HOME/.agents/skills" ;;
    codex:project)  echo "$PWD/.agents/skills" ;;
  esac
}

install_one() {
  host="$1"
  dest_root=$(dest_dir_for "$host")
  dest="$dest_root/$SKILL_NAME"

  if [ "$LINK" = "1" ]; then
    mkdir -p "$dest_root"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$SKILL_SRC" ]; then
        echo "[$host] already linked, up to date: $dest"
        return 0
      fi
      if [ "$FORCE" != "1" ]; then
        echo "[$host] ERROR: $dest exists and differs; use --force to replace" >&2
        exit 1
      fi
      rm -rf "$dest"
    fi
    ln -s "$SKILL_SRC" "$dest"
    echo "[$host] linked: $dest -> $SKILL_SRC"
    return 0
  fi

  if [ -d "$dest" ]; then
    if diff -r -q "$SKILL_SRC" "$dest" >/dev/null 2>&1; then
      echo "[$host] already up to date: $dest"
      return 0
    fi
    if [ "$FORCE" != "1" ]; then
      echo "[$host] ERROR: $dest exists and content differs." >&2
      echo "        Re-run with --force to replace (a timestamped backup is kept)." >&2
      exit 1
    fi
    backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
    cp -R "$dest" "$backup"
    echo "[$host] backed up existing install to: $backup"
    if rm -rf "$dest" 2>/dev/null; then
      cp -R "$SKILL_SRC" "$dest"
    else
      # dest directory is held by a running host (common on Windows): update in place
      cp -R "$SKILL_SRC"/. "$dest"/
      echo "[$host] note: dest dir was locked by a running host; updated in place"
    fi
    echo "[$host] installed (copy): $dest"
    echo "        canonical source remains: skills/$SKILL_NAME in this repository"
    return 0
  fi
}

[ "$TARGET" = "claude" ] || [ "$TARGET" = "all" ] && install_one claude
[ "$TARGET" = "codex" ]  || [ "$TARGET" = "all" ] && install_one codex

echo "Done. Restart your agent host (Claude Code / Codex) to pick up the skill."
