#!/usr/bin/env bash
#
# dev-sync.sh — copy this working tree into the installed /watch plugin cache so
# local edits are picked up by Claude Code without publishing a release.
#
# The install path is resolved from ~/.claude/plugins/installed_plugins.json, so
# it follows version bumps automatically. Override it by passing a path as $1 or
# setting WATCH_INSTALL_PATH. Pass --dry-run to preview without writing.
#
# Usage:
#   ./dev-sync.sh                 # sync into the resolved install path
#   ./dev-sync.sh --dry-run       # show what would change
#   ./dev-sync.sh /some/other/dir # sync into an explicit path
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_KEY="watch@claude-video"
INSTALLED_JSON="${HOME}/.claude/plugins/installed_plugins.json"

DRY_RUN=()
DEST=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=(--dry-run --itemize-changes) ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) DEST="$arg" ;;
  esac
done

# Resolve the destination install path if not given explicitly.
if [[ -z "$DEST" ]]; then
  DEST="${WATCH_INSTALL_PATH:-}"
fi
if [[ -z "$DEST" ]]; then
  if [[ ! -f "$INSTALLED_JSON" ]]; then
    echo "error: $INSTALLED_JSON not found; pass an install path explicitly" >&2
    exit 1
  fi
  DEST="$(PLUGIN_KEY="$PLUGIN_KEY" python3 - "$INSTALLED_JSON" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1]))
key = os.environ["PLUGIN_KEY"]
records = data.get("plugins", {}).get(key, [])
# Prefer a record whose installPath actually exists on disk.
paths = [r.get("installPath") for r in records if r.get("installPath")]
for p in paths:
    if os.path.isdir(p):
        print(p); break
else:
    print(paths[0] if paths else "")
PY
)"
fi

if [[ -z "$DEST" ]]; then
  echo "error: could not resolve an install path for '$PLUGIN_KEY'" >&2
  echo "       install the plugin first, or pass a path: scripts/dev-sync.sh /path/to/install" >&2
  exit 1
fi
if [[ ! -d "$DEST" ]]; then
  echo "error: install path does not exist: $DEST" >&2
  exit 1
fi

echo "source: $REPO_ROOT"
echo "dest:   $DEST"
echo

# Mirror shipped files only. Dev-only artifacts and runtime state are excluded.
# No --delete: the cache holds runtime state (.in_use/) we must not touch.
rsync -a ${DRY_RUN[@]+"${DRY_RUN[@]}"} \
  --exclude '.git/' \
  --exclude '.venv/' \
  --exclude '.pytest_cache/' \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude '.DS_Store' \
  --exclude '.in_use/' \
  --exclude 'tests/' \
  --exclude 'docs/' \
  --exclude 'dist/' \
  --exclude 'V2_*.md' \
  --exclude 'dev-sync.sh' \
  "$REPO_ROOT/" "$DEST/"

echo "done."
